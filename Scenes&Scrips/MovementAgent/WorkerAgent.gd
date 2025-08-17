extends Node
class_name WorkerAgent

@export var tilemap_layer_path: NodePath   # usually your Floor layer (or leave empty to use 'floor_layer' group)
@export var work_seconds: float = 1.2      # time to "dig"
@export var idle_move_every_min: float = 1.2
@export var idle_move_every_max: float = 2.0

var _tilemap: TileMapLayer
var _body: Node2D
var _agent: MovementAgent
var _rng := RandomNumberGenerator.new()
var _current_job: Job = null
var _idling := true

@export var carry_capacity: int = 2

const DIR4 := [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]

func _ready():
	_rng.randomize()
	add_to_group("workers")
	_body = get_parent() as Node2D
	_agent = _body.get_node("MovementAgent") as MovementAgent

	if tilemap_layer_path != NodePath(""):
		_tilemap = get_node_or_null(tilemap_layer_path) as TileMapLayer
	if _tilemap == null:
		_tilemap = get_tree().get_first_node_in_group("floor_layer") as TileMapLayer

	_schedule_idle_tick()

func _schedule_idle_tick():
	var wait := _rng.randf_range(idle_move_every_min, idle_move_every_max)
	_idle_tick(wait)

func _idle_tick(delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if _current_job == null:
		# Ask JobManager for work
		var j := JobManager.request_job(_body)
		if j != null:
			_current_job = j
			_go_do_job(j)
		else:
			_idle_shuffle()
	_schedule_idle_tick()

func _idle_shuffle():
	# Pick a random walkable neighbor; move one step if any
	if _tilemap == null: return
	var here: Vector2i = GridNav.world_to_cell(_body.global_position, _tilemap)
	var opts: Array[Vector2i] = []
	for d in DIR4:
		var n = here + d
		if GridNav.is_walkable(n):
			opts.append(n)
	if opts.is_empty():
		return
	var dest := opts[_rng.randi_range(0, opts.size()-1)]
	_agent.set_destination_cell(dest)  # fire-and-forget small nudge

func get_status_text() -> String:
	# Minimal + safe: describe what the worker is doing.
	# Customize later if your Job exposes nicer info.
	if _current_job != null:
		# Try to show a job "kind" if present; else generic.
		var kind := ""
		if _current_job.has_method("get_kind"):
			kind = String(_current_job.get_kind())
		elif "kind" in _current_job:
			kind = str(_current_job.kind)
		return "Working" + (": " + kind if kind != "" else "")
	# If agent is moving you can say Walking; otherwise Idle.
	return "Idle"



func _do_simple_work(job: Job) -> void:
	_agent.set_destination_cell(job.target_cell)
	await _agent.arrived
	var here := GridNav.world_to_cell(_body.global_position, _tilemap)
	if here != job.target_cell:
		JobManager.reopen_job(job)
		_current_job = null
		return
	JobManager.complete_job(job)
	_current_job = null

func _go_do_job(job: Job) -> void:
	
	if job.type.begins_with("haul_"):
		await _do_haul(job)
		return
	
	if job.type == "well_operate":
		await _do_stand_and_work(job)
		return	
	
	var attempts: int = 0
	while attempts < 3:
		var adj: Variant = _find_adjacent_for_job(job)
		if adj == null:
			JobManager.cancel_job(job)
			_current_job = null
			return

		var adj_cell: Vector2i = adj as Vector2i
		_agent.set_destination_cell(adj_cell)

		# wait for the real arrival (zero-step will emit next frame)
		await _agent.arrived

		# verify we truly reached the intended adjacent cell
		var here: Vector2i = GridNav.world_to_cell(_body.global_position, _tilemap)
		if here != adj_cell:
			attempts += 1
			continue

		# do the work now that we're adjacent
		await get_tree().create_timer(work_seconds).timeout

		# job might have changed while we waited
		if job.status == Job.Status.CANCELLED or job.status == Job.Status.DONE:
			_current_job = null
			return

		JobManager.complete_job(job)
		_current_job = null
		_self_rescue_if_trapped()
		return

	# if we couldn't confirm arrival after a few tries, reopen so another worker can try
	job.status = Job.Status.OPEN
	job.reserved_by = NodePath("")
	JobManager.job_updated.emit(job)
	_current_job = null

func _do_stand_and_work(job: Job) -> void:
	var stand_cell: Vector2i = job.data.get("stand_cell", job.target_cell)

	_agent.set_destination_cell(stand_cell)
	await _agent.arrived

	var here: Vector2i = GridNav.world_to_cell(_body.global_position, _tilemap)
	if here != stand_cell:
		JobManager.reopen_job(job)
		_current_job = null
		return

	JobManager.start_job(job)

	# do the work
	await get_tree().create_timer(work_seconds).timeout

	# job could have been cancelled while we waited
	if job.status == Job.Status.CANCELLED or job.status == Job.Status.DONE:
		_current_job = null
		return

	JobManager.complete_job(job)
	_current_job = null
	_self_rescue_if_trapped()

func _do_haul(job: Job) -> void:
	var kind: String = String(job.data.get("kind", "rock"))

	# 1) go to the PICKUP cell (ground item, or a bucket if source=="bucket")
	_agent.set_destination_cell(job.target_cell)
	await _agent.arrived

	var here: Vector2i = GridNav.world_to_cell(_body.global_position, _tilemap)
	if here != job.target_cell:
		JobManager.reopen_job(job)
		_current_job = null
		return

	# flags we use a couple times
	var is_farm_delivery := job.data.has("deposit_target") and String(job.data["deposit_target"]) == "farm"
	var source := String(job.data.get("source", ""))  # "" | "ground" | "bucket"

	# 2) PICKUP
	if kind == "water" and source == "bucket":
		# water comes out of a bucket's stored count (not ground)
		JobManager.start_job(job)
		if not WaterSystem.consume_bucket_withdraw(job.target_cell):
			# couldn't consume (stale reservation, someone else took it, etc.)
			# -> release the reservation and clear the farm's pending so it can re-request
			WaterSystem.release_bucket_withdraw(job.target_cell)
			if is_farm_delivery and job.data.has("deposit_cell"):
				WaterSystem.clear_pending_for_farm(job.data["deposit_cell"])
			JobManager.reopen_job(job)
			_current_job = null
			return
	else:
		# generic ground pickup (rock/carrot/water already claimed at reserve time)
		if not JobManager.has_ground_item(job.target_cell, kind):
			if is_farm_delivery and job.data.has("deposit_cell"):
				WaterSystem.clear_pending_for_farm(job.data["deposit_cell"])
			JobManager.reopen_job(job)
			_current_job = null
			return

		JobManager.start_job(job)
		if not JobManager.take_item(job.target_cell, kind, 1):
			if is_farm_delivery and job.data.has("deposit_cell"):
				WaterSystem.clear_pending_for_farm(job.data["deposit_cell"])
			JobManager.reopen_job(job)
			_current_job = null
			return


	# 3) DELIVER
	# 3a) deliver to FARM
	if is_farm_delivery:
		if not job.data.has("deposit_cell"):
			JobManager.cancel_job(job)  # stale job; fail fast
			_current_job = null
			return
		var farm_cell: Vector2i = job.data["deposit_cell"]
		_agent.set_destination_cell(farm_cell)
		await _agent.arrived
		JobManager.complete_job(job)
		_current_job = null
		_self_rescue_if_trapped()
		return

	# 3b) deliver to BUCKET
	if job.data.has("deposit_target") and String(job.data["deposit_target"]) == "bucket":
		if not job.data.has("deposit_cell"):
			JobManager.cancel_job(job)
			_current_job = null
			return
		var depot_b: Vector2i = job.data["deposit_cell"]
		_agent.set_destination_cell(depot_b)
		await _agent.arrived
		JobManager.complete_job(job)
		_current_job = null
		_self_rescue_if_trapped()
		return

	# 3c) deliver to specific deposit_cell (treasury etc.)
	if job.data.has("deposit_cell"):
		var depot: Vector2i = job.data["deposit_cell"]
		_agent.set_destination_cell(depot)
		await _agent.arrived
		JobManager.complete_job(job)
		_current_job = null
		_self_rescue_if_trapped()
		return

	# 3d) fallback: no destination—reopen
	JobManager.reopen_job(job)
	_current_job = null


func _find_adjacent_for_job(job: Job) -> Variant:
	var start_cell: Vector2i = GridNav.world_to_cell(_body.global_position, _tilemap)
	for d in DIR4:
		var n = job.target_cell + d
		if GridNav.is_walkable(n):
			var path = GridNav.find_path_cells(start_cell, n)
			if not path.is_empty():
				return n
	return null

func _self_rescue_if_trapped() -> void:
	if _tilemap == null:
		return
	var here: Vector2i = GridNav.world_to_cell(_body.global_position, _tilemap)
	# if none of the 4 neighbors are walkable, queue a dig on any adjacent wall
	var has_escape: bool = false
	for d: Vector2i in DIR4:
		var n: Vector2i = here + d
		if GridNav.is_walkable(n):
			has_escape = true
			break
	if has_escape:
		return
	# queue one adjacent dig (first wall found)
	for d2: Vector2i in DIR4:
		var wcell: Vector2i = here + d2
		if JobManager.walls_layer != null and JobManager.walls_layer.get_cell_source_id(wcell) != -1:
			JobManager.ensure_dig_job(wcell)
			break

func _wait_for_arrival_dynamic(from_cell: Vector2i, to_cell: Vector2i) -> bool:
	var path: PackedVector2Array = GridNav.find_path_cells(from_cell, to_cell)
	var steps: int = max(0, path.size() - 1)
	var expected: float = 0.0
	if _agent != null and _agent.tiles_per_second > 0.0:
		expected = float(steps) / _agent.tiles_per_second

	# generous timeout: distance time * 1.8 + buffer
	var timeout: float = expected * 1.8 + 0.5
	var arrived_flag: bool = false
	_agent.arrived.connect(func() -> void: arrived_flag = true, CONNECT_ONE_SHOT)

	var elapsed: float = 0.0
	while not arrived_flag and elapsed < timeout:
		await get_tree().process_frame
		elapsed += get_process_delta_time()

	return arrived_flag
