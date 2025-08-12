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

# items on ground: cell -> {"rock": count}
var items_on_ground: Dictionary = {}

# treasury tracking
@export var treasury_capacity_per_tile: int = 10
var treasury_cells: Dictionary = {}	# cell(Vector2i) -> true
var treasury_stored_rock: int = 0
var treasury_reserved: int = 0	# slots reserved by in-flight haul jobs

var items_layer: TileMapLayer

# ground items: cell -> {"rock": count}

# rock visuals
@export var rock_stack_max_per_cell: int = 12
@export var rock_source_id: int = -1
@export var rock_atlas_coords_0: Vector2i = Vector2i.ZERO
@export var rock_atlas_coords_1: Vector2i = Vector2i.ZERO
@export var rock_atlas_coords_2: Vector2i = Vector2i.ZERO
@export var rock_atlas_coords_3: Vector2i = Vector2i.ZERO
@export var rock_alt: int = 0
var treasury_contents: Dictionary = {}		# cell(Vector2i) -> {"rock": count}
var treasury_reserved_per_cell: Dictionary = {}	# cell -> reserved slots
signal items_changed(cell: Vector2i)


# rock visuals (keep your existing vars)
# @export var rock_stack_max_per_cell: int = 12
# @export var rock_source_id: int = -1
# @export var rock_atlas_coords_0..3, rock_alt


func init(floor: TileMapLayer, walls: TileMapLayer, rooms: TileMapLayer, items: TileMapLayer) -> void:
	floor_layer = floor
	walls_layer = walls
	rooms_layer = rooms
	items_layer = items
	_rebuild_treasury_cells()
	treasury_reserved = 0

func set_rock_tiles(source_id: int, a0: Vector2i, a1: Vector2i, a2: Vector2i, a3: Vector2i, alternative: int) -> void:
	rock_source_id = source_id
	rock_atlas_coords_0 = a0
	rock_atlas_coords_1 = a1
	rock_atlas_coords_2 = a2
	rock_atlas_coords_3 = a3
	rock_alt = alternative

func _rebuild_treasury_cells() -> void:
	treasury_cells.clear()
	if rooms_layer == null:
		return
	var used: PackedVector2Array = rooms_layer.get_used_cells()
	for c: Vector2i in used:
		treasury_cells[c] = true
		if not treasury_contents.has(c):
			treasury_contents[c] = {"rock": 0}
		if not treasury_reserved_per_cell.has(c):
			treasury_reserved_per_cell[c] = 0

func _cell_capacity(cell: Vector2i) -> int:
	return treasury_capacity_per_tile

func _cell_stored(cell: Vector2i) -> int:
	if not treasury_contents.has(cell):
		return 0
	return int((treasury_contents[cell] as Dictionary).get("rock", 0))

func _cell_reserved(cell: Vector2i) -> int:
	return int(treasury_reserved_per_cell.get(cell, 0))

func _cell_free_effective(cell: Vector2i) -> int:
	return _cell_capacity(cell) - _cell_stored(cell) - _cell_reserved(cell)

func _any_treasury_space_available() -> bool:
	for k in treasury_cells.keys():
		if _cell_free_effective(k) > 0:
			return true
	return false


func get_treasury_capacity() -> int:
	return treasury_cells.size() * treasury_capacity_per_tile

func get_treasury_space_effective() -> int:
	return get_treasury_capacity() - treasury_stored_rock - treasury_reserved

func drop_item(cell: Vector2i, kind: String, count: int) -> void:
	var bucket: Dictionary = items_on_ground.get(cell, {})
	var cur: int = int(bucket.get(kind, 0))
	bucket[kind] = cur + count
	items_on_ground[cell] = bucket
	_refresh_item_cell_visual(cell)
	items_changed.emit(cell)	# <-- NEW

func has_ground_item(cell: Vector2i, kind: String) -> bool:
	if not items_on_ground.has(cell):
		return false
	var bucket: Dictionary = items_on_ground[cell]
	return int(bucket.get(kind, 0)) > 0

func take_item(cell: Vector2i, kind: String, count: int) -> bool:
	if not has_ground_item(cell, kind):
		return false
	var bucket: Dictionary = items_on_ground[cell]
	var cur: int = int(bucket.get(kind, 0))
	var newv: int = max(0, cur - count)
	bucket[kind] = newv
	if newv == 0:
		bucket.erase(kind)
	if bucket.size() == 0:
		items_on_ground.erase(cell)
	else:
		items_on_ground[cell] = bucket
	_refresh_item_cell_visual(cell)
	items_changed.emit(cell)
	return true

func find_nearest_reachable_treasury_cell_with_space(from_cell: Vector2i) -> Variant:
	var found: bool = false
	var best_cell: Vector2i = Vector2i.ZERO
	var best_steps: int = 0
	for key in treasury_cells.keys():
		var tcell: Vector2i = key
		if _cell_free_effective(tcell) <= 0:
			continue
		var path: PackedVector2Array = GridNav.find_path_cells(from_cell, tcell)
		if not path.is_empty():
			var steps: int = max(0, path.size() - 1)
			if not found or steps < best_steps:
				found = true
				best_steps = steps
				best_cell = tcell
	if found:
		return best_cell
	return null

func _reserve_treasury_cell(cell: Vector2i) -> void:
	var cur: int = int(treasury_reserved_per_cell.get(cell, 0))
	treasury_reserved_per_cell[cell] = cur + 1
	treasury_reserved += 1

func _release_treasury_cell(cell: Vector2i) -> void:
	if treasury_reserved > 0:
		treasury_reserved -= 1
	var cur: int = int(treasury_reserved_per_cell.get(cell, 0))
	treasury_reserved_per_cell[cell] = max(0, cur - 1)


func create_haul_job(cell: Vector2i, kind: String) -> Job:
	if not has_ground_item(cell, kind):
		return null
	var j: Job = Job.new()
	j.id = _next_id
	_next_id += 1
	j.type = "haul_rock"
	j.target_cell = cell
	j.data["kind"] = kind
	j.data["count"] = 1
	jobs.append(j)
	job_added.emit(j)
	return j

func ensure_haul_job(cell: Vector2i, kind: String) -> void:
	if has_job_at(cell, "haul_rock"):
		return
	if has_ground_item(cell, kind):
		create_haul_job(cell, kind)

func remove_haul_job_at(cell: Vector2i) -> void:
	var j: Job = get_job_at(cell, "haul_rock")
	if j != null and (j.status == Job.Status.OPEN or j.status == Job.Status.RESERVED):
		cancel_job(j)

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
	for j: Job in jobs:
		if j.is_open():
			if j.type == "haul_rock":
				if not _any_treasury_space_available():
					continue
				if not has_ground_item(j.target_cell, "rock"):
					j.status = Job.Status.CANCELLED
					job_updated.emit(j)
					continue

				var start_cell: Vector2i = GridNav.world_to_cell(worker.global_position, floor_layer)
				var path_to_item: PackedVector2Array = GridNav.find_path_cells(start_cell, j.target_cell)
				if path_to_item.is_empty():
					continue

				var depot_variant = find_nearest_reachable_treasury_cell_with_space(j.target_cell)
				if depot_variant == null:
					continue

				var depot_cell: Vector2i = depot_variant as Vector2i
				j.data["deposit_cell"] = depot_cell			# <- always a Vector2i
				j.status = Job.Status.RESERVED
				j.reserved_by = worker.get_path()
				_reserve_treasury_cell(depot_cell)			# <- per-cell reservation
				job_updated.emit(j)
				return j

			else:
				var adj = _find_reachable_adjacent(worker, j.target_cell)
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
		# drop one rock on the ground where we dug
		drop_item(job.target_cell, "rock", 1)

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
		# place Treasury tile + register capacity + init storage at this cell
		_ensure_room_tile_defaults(job.data.get("room_kind", "treasury"))
		if room_treasury_source_id == -1:
			push_error("JobManager: room_treasury_source_id not set and no sample room tile found.")
		else:
			rooms_layer.set_cell(job.target_cell, room_treasury_source_id, room_treasury_atlas_coords, room_treasury_alt)
			treasury_cells[job.target_cell] = true
			if not treasury_contents.has(job.target_cell):
				treasury_contents[job.target_cell] = {"rock": 0}
			if not treasury_reserved_per_cell.has(job.target_cell):
				treasury_reserved_per_cell[job.target_cell] = 0
			# make sure Items layer reflects any stored/ground piles here
			_refresh_item_cell_visual(job.target_cell)

	elif job.type == "unassign_room":
		# spill stored rocks back onto the ground at this cell, then remove room
		if rooms_layer != null:
			var stored: int = _cell_stored(job.target_cell)
			if stored > 0:
				drop_item(job.target_cell, "rock", stored)
				if treasury_contents.has(job.target_cell):
					var bucket: Dictionary = treasury_contents[job.target_cell]
					if bucket.has("rock"):
						bucket["rock"] = 0
						treasury_contents[job.target_cell] = bucket
			rooms_layer.erase_cell(job.target_cell)
			_refresh_item_cell_visual(job.target_cell)
			treasury_cells.erase(job.target_cell)
			treasury_reserved_per_cell.erase(job.target_cell)

	elif job.type == "haul_rock":
		if job.data.has("deposit_cell"):
			var depot_cell: Vector2i = job.data["deposit_cell"] as Vector2i
			_release_treasury_cell(depot_cell)
			_add_treasury_item(depot_cell, "rock", int(job.data.get("count", 1)))
		else:
			# fallback only if older jobs exist with no deposit set
			var depot = find_nearest_reachable_treasury_cell_with_space(job.target_cell)
			if depot != null:
				_add_treasury_item(depot as Vector2i, "rock", int(job.data.get("count", 1)))

	job.status = Job.Status.DONE
	job_completed.emit(job)

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

func reopen_job(job: Job) -> void:
	if job == null:
		return
	if job.type == "haul_rock" and job.data.has("deposit_cell"):
		_release_treasury_cell(job.data["deposit_cell"])
	# NEW: show ghost again if we put the rock back
	if job.type == "haul_rock" and job.data.has("picked_up"):
		job.data["picked_up"] = false
	job.status = Job.Status.OPEN
	job.reserved_by = NodePath("")
	job_updated.emit(job)

func cancel_job(job: Job) -> void:
	if job == null:
		return
	if job.type == "haul_rock" and job.data.has("deposit_cell"):
		_release_treasury_cell(job.data["deposit_cell"])
	job.status = Job.Status.CANCELLED
	job_updated.emit(job)


func _refresh_item_cell_visual(cell: Vector2i) -> void:
	if items_layer == null:
		return

	var ground: int = 0
	if items_on_ground.has(cell):
		ground = int((items_on_ground[cell] as Dictionary).get("rock", 0))
	var stored: int = _cell_stored(cell)

	var count: int = ground + stored
	if count <= 0:
		items_layer.erase_cell(cell)
		return

	if rock_source_id == -1:
		return

	var idx: int = _rock_index_for_count(count)
	var atlas: Vector2i = rock_atlas_coords_0
	if idx == 1:
		atlas = rock_atlas_coords_1
	elif idx == 2:
		atlas = rock_atlas_coords_2
	elif idx == 3:
		atlas = rock_atlas_coords_3

	items_layer.set_cell(cell, rock_source_id, atlas, rock_alt)

func _add_treasury_item(cell: Vector2i, kind: String, count: int) -> void:
	if not treasury_contents.has(cell):
		treasury_contents[cell] = {}
	var bucket: Dictionary = treasury_contents[cell]
	var cur: int = int(bucket.get(kind, 0))
	bucket[kind] = cur + count
	treasury_contents[cell] = bucket
	_refresh_item_cell_visual(cell)


func _rock_index_for_count(count: int) -> int:
	var maxv: int = max(1, rock_stack_max_per_cell)
	var r: float = float(count) / float(maxv)
	if r <= 0.25:
		return 0
	elif r <= 0.5:
		return 1
	elif r <= 0.75:
		return 2
	else:
		return 3
