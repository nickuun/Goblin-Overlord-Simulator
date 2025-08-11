extends Node

signal job_added(job: Job)
signal job_updated(job: Job)
signal job_completed(job: Job)

@export var build_wall_source_id: int = 0
@export var build_wall_atlas_coords: Vector2i = Vector2i(3, 11)
@export var build_wall_alternative_tile: int = 0

var jobs: Array[Job] = []
var _next_id: int = 1

var floor_layer: TileMapLayer
var walls_layer: TileMapLayer

const DIR4: Array[Vector2i] = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]

var rooms_layer: TileMapLayer

@export var room_treasury_source_id: int = -1
@export var room_treasury_atlas_coords: Vector2i = Vector2i.ZERO
@export var room_treasury_alt: int = 0

func init(floor: TileMapLayer, walls: TileMapLayer, rooms: TileMapLayer) -> void:
	floor_layer = floor
	walls_layer = walls
	rooms_layer = rooms

func create_dig_job(cell: Vector2i) -> Job:
	if walls_layer == null:
		push_error("JobManager: walls_layer not set")
		return null

	var src_id: int = walls_layer.get_cell_source_id(cell)
	if src_id == -1:
		return null

	var j: Job = Job.new()
	j.id = _next_id
	_next_id += 1
	j.type = "dig_wall"
	j.target_cell = cell
	jobs.append(j)
	job_added.emit(j)
	return j

func request_job(worker: Node2D) -> Job:
	# Hand out the first reachable OPEN job
	for j: Job in jobs:
		if j.is_open():
			var adj: Variant = _find_reachable_adjacent(worker, j.target_cell)
			if adj != null:
				j.status = Job.Status.RESERVED
				j.reserved_by = worker.get_path()
				job_updated.emit(j)
				return j
	return null

func start_job(job: Job) -> void:
	if job == null:
		return
	job.status = Job.Status.ACTIVE
	job_updated.emit(job)

func complete_job(job: Job) -> void:
	if job == null:
		return

	if job.type == "dig_wall":
		if walls_layer != null:
			walls_layer.erase_cell(job.target_cell)
		GridNav.astar.set_point_solid(job.target_cell, false)

	elif job.type == "build_wall":
		_ensure_build_tile_defaults()
		if _is_cell_occupied_by_worker(job.target_cell):
			job.status = Job.Status.OPEN
			job.reserved_by = NodePath("")
			job_updated.emit(job)
			return
		if build_wall_source_id == -1:
			push_error("JobManager: build_wall_source_id not set and no sample wall tile found.")
		else:
			walls_layer.set_cell(job.target_cell, build_wall_source_id, build_wall_atlas_coords, build_wall_alternative_tile)
			GridNav.astar.set_point_solid(job.target_cell, true)

	elif job.type == "assign_room":
		_ensure_room_tile_defaults(job.data.get("room_kind", "treasury"))
		if room_treasury_source_id == -1:
			push_error("JobManager: room_treasury_source_id not set and no sample room tile found.")
		else:
			rooms_layer.set_cell(job.target_cell, room_treasury_source_id, room_treasury_atlas_coords, room_treasury_alt)

	elif job.type == "unassign_room":
		if rooms_layer != null:
			rooms_layer.erase_cell(job.target_cell)

	job.status = Job.Status.DONE
	job_completed.emit(job)


func cancel_job(job: Job) -> void:
	if job == null:
		return
	job.status = Job.Status.CANCELLED
	job_updated.emit(job)

func _find_reachable_adjacent(worker: Node2D, target_cell: Vector2i) -> Variant:
	if floor_layer == null:
		return null

	var start_cell: Vector2i = GridNav.world_to_cell(worker.global_position, floor_layer)

	# Try 4 neighbors of the target; return the first walkable with a path
	for d: Vector2i in DIR4:
		var n: Vector2i = target_cell + d
		if not GridNav.is_walkable(n):
			continue
		var path: PackedVector2Array = GridNav.find_path_cells(start_cell, n)
		if not path.is_empty():
			return n
	return null

func create_build_job(cell: Vector2i) -> Job:
	if walls_layer == null:
		push_error("JobManager: walls_layer not set")
		return null

	var src_id: int = walls_layer.get_cell_source_id(cell)
	if src_id != -1:
		return null

	var j: Job = Job.new()
	j.id = _next_id
	_next_id += 1
	j.type = "build_wall"
	j.target_cell = cell
	jobs.append(j)
	job_added.emit(j)
	return j

func _ensure_build_tile_defaults() -> void:
	if walls_layer == null:
		return
	if build_wall_source_id != -1:
		return

	var used: PackedVector2Array = walls_layer.get_used_cells()
	if used.size() > 0:
		var sample: Vector2i = used[0]
		build_wall_source_id = walls_layer.get_cell_source_id(sample)
		var ac: Vector2i = walls_layer.get_cell_atlas_coords(sample)
		build_wall_atlas_coords = ac
		var alt: int = 0
		if walls_layer.has_method("get_cell_alternative_tile"):
			alt = walls_layer.get_cell_alternative_tile(sample)
		build_wall_alternative_tile = alt
	else:
		push_warning("JobManager: no existing wall tiles found; set build_wall_source_id / build_wall_atlas_coords in code or Inspector.")

func get_job_at(cell: Vector2i, type: String) -> Job:
	for j: Job in jobs:
		if (j.status != Job.Status.DONE and j.status != Job.Status.CANCELLED) and j.type == type and j.target_cell == cell:
			return j
	return null

func has_job_at(cell: Vector2i, type: String) -> bool:
	return get_job_at(cell, type) != null

func ensure_dig_job(cell: Vector2i) -> void:
	if walls_layer == null:
		return
	var src_id: int = walls_layer.get_cell_source_id(cell)
	if src_id == -1:
		return
	if has_job_at(cell, "dig_wall"):
		return
	create_dig_job(cell)

func ensure_build_job(cell: Vector2i) -> void:
	if walls_layer == null:
		return
	var src_id: int = walls_layer.get_cell_source_id(cell)
	if src_id != -1:
		return
	if has_job_at(cell, "build_wall"):
		return
	create_build_job(cell)

func remove_job_at(cell: Vector2i, type: String) -> void:
	var j: Job = get_job_at(cell, type)
	if j == null:
		return
	if j.status == Job.Status.OPEN or j.status == Job.Status.RESERVED:
		cancel_job(j)

func _is_cell_occupied_by_worker(cell: Vector2i) -> bool:
	var floor := floor_layer
	if floor == null:
		return false
	for n in get_tree().get_nodes_in_group("workers"):
		if n is Node2D:
			var wcell: Vector2i = GridNav.world_to_cell(n.global_position, floor)
			if wcell == cell:
				return true
	return false

func create_assign_room_job(cell: Vector2i, room_kind: String) -> Job:
	if rooms_layer == null:
		push_error("JobManager: rooms_layer not set")
		return null
	# only assign on non-wall cells
	if walls_layer != null and walls_layer.get_cell_source_id(cell) != -1:
		return null
	# skip if already assigned
	if rooms_layer.get_cell_source_id(cell) != -1:
		return null
	var j: Job = Job.new()
	j.id = _next_id
	_next_id += 1
	j.type = "assign_room"
	j.target_cell = cell
	j.data["room_kind"] = room_kind
	jobs.append(j)
	job_added.emit(j)
	return j

func create_unassign_room_job(cell: Vector2i) -> Job:
	if rooms_layer == null:
		return null
	if rooms_layer.get_cell_source_id(cell) == -1:
		return null
	var j: Job = Job.new()
	j.id = _next_id
	_next_id += 1
	j.type = "unassign_room"
	j.target_cell = cell
	jobs.append(j)
	job_added.emit(j)
	return j

func ensure_assign_room_job(cell: Vector2i, room_kind: String) -> void:
	if not has_job_at(cell, "assign_room") and rooms_layer != null and rooms_layer.get_cell_source_id(cell) == -1:
		create_assign_room_job(cell, room_kind)

func ensure_unassign_room_job(cell: Vector2i) -> void:
	if not has_job_at(cell, "unassign_room") and rooms_layer != null and rooms_layer.get_cell_source_id(cell) != -1:
		create_unassign_room_job(cell)

func remove_room_job_at(cell: Vector2i) -> void:
	var j: Job = get_job_at(cell, "assign_room")
	if j == null:
		j = get_job_at(cell, "unassign_room")
	if j != null and (j.status == Job.Status.OPEN or j.status == Job.Status.RESERVED):
		cancel_job(j)

func _ensure_room_tile_defaults(room_kind: String) -> void:
	if rooms_layer == null:
		return
	if room_treasury_source_id != -1:
		return
	var used: PackedVector2Array = rooms_layer.get_used_cells()
	if used.size() > 0:
		var sample: Vector2i = used[0]
		room_treasury_source_id = rooms_layer.get_cell_source_id(sample)
		room_treasury_atlas_coords = rooms_layer.get_cell_atlas_coords(sample)
		var alt: int = 0
		if rooms_layer.has_method("get_cell_alternative_tile"):
			alt = rooms_layer.get_cell_alternative_tile(sample)
		room_treasury_alt = alt
