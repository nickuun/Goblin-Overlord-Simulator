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

# which kind this cell is currently stacking; "" = unassigned
var treasury_stack_kind: Dictionary = {}				# cell(Vector2i) -> String
# per-cell, per-kind reservations
var treasury_reserved_per_cell_kind: Dictionary = {}	# cell -> {kind: int}

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

@export var room_farm_source_id: int = 1
@export var room_farm_atlas_coords: Vector2i = Vector2i(50,17)
@export var room_farm_alt: int = 0

@export var carrot_stack_max_per_cell: int = 12
@export var carrot_source_id: int = -1
@export var carrot_atlas_coords_0: Vector2i = Vector2i.ZERO
@export var carrot_atlas_coords_1: Vector2i = Vector2i.ZERO
@export var carrot_atlas_coords_2: Vector2i = Vector2i.ZERO
@export var carrot_atlas_coords_3: Vector2i = Vector2i.ZERO
@export var carrot_alt: int = 0

signal inventory_changed()

var treasury_cell_area_id: Dictionary = {}				# cell -> area_id
var area_id_cells: Dictionary = {}						# area_id -> Array[Vector2i]
var treasury_area_rules: Dictionary = {}				# area_id -> {"any":bool,"allowed":Array[String]}
var _prev_cell_area_id: Dictionary = {}					# for merging rule carry-over

# rock visuals (keep your existing vars)
# @export var rock_stack_max_per_cell: int = 12
# @export var rock_source_id: int = -1
# @export var rock_atlas_coords_0..3, rock_alt

# --- Furniture tiles ---
@export var well_source_id: int = 0
@export var well_atlas_coords: Vector2i = Vector2i(38,16)
@export var well_alt: int = 0

@export var bucket_source_id: int = 0
@export var bucket_atlas_coords: Vector2i = Vector2i(37,16)
@export var bucket_alt: int = 0

var furniture_layer: TileMapLayer
var well_cells: Dictionary = {}		# cell -> true
var bucket_cells: Dictionary = {}	# cell -> true

# --- Bucket contents/reservations (water only for now) ---
@export var bucket_capacity_per_bucket: int = 4
var bucket_water: Dictionary = {}				# cell -> int
var bucket_reserved: Dictionary = {}			# cell -> int

# --- Water visuals (optional; set if you have sprites) ---
@export var water_stack_max_per_cell: int = 12
@export var water_source_id: int = 0
@export var water_atlas_coords_0: Vector2i = Vector2i(37,16)
@export var water_atlas_coords_1: Vector2i = Vector2i(37,16)
@export var water_atlas_coords_2: Vector2i = Vector2i(37,16)
@export var water_atlas_coords_3: Vector2i = Vector2i(37,16)
@export var water_alt: int = 0

func _ready() -> void:
	var ui := get_node_or_null("/root/DevUI")
	if ui != null:
		ui.treasury_rules_changed.connect(on_treasury_rules_changed_from_ui)

func init(floor: TileMapLayer, walls: TileMapLayer, rooms: TileMapLayer, furniture: TileMapLayer, items: TileMapLayer) -> void:
	floor_layer = floor
	walls_layer = walls
	rooms_layer = rooms
	furniture_layer = furniture
	items_layer = items
	_rebuild_treasury_cells()
	treasury_reserved = 0
	_recompute_treasury_areas()

func set_rock_tiles(source_id: int, a0: Vector2i, a1: Vector2i, a2: Vector2i, a3: Vector2i, alternative: int) -> void:
	rock_source_id = source_id
	rock_atlas_coords_0 = a0
	rock_atlas_coords_1 = a1
	rock_atlas_coords_2 = a2
	rock_atlas_coords_3 = a3
	rock_alt = alternative

func set_farm_tiles(source_id: int, a0: Vector2i, a1: Vector2i, a2: Vector2i, a3: Vector2i, alternative: int) -> void:
	carrot_source_id = source_id
	carrot_atlas_coords_0 = a0
	carrot_atlas_coords_1 = a1
	carrot_atlas_coords_2 = a2
	carrot_atlas_coords_3 = a3
	carrot_alt = alternative

func _rebuild_treasury_cells() -> void:
	treasury_cells.clear()
	if rooms_layer == null:
		return
	var used: PackedVector2Array = rooms_layer.get_used_cells()
	for c: Vector2i in used:
		treasury_cells[c] = true
		if not treasury_contents.has(c):
			treasury_contents[c] = {"rock": 0, "carrot": 0}
		if not treasury_reserved_per_cell.has(c):
			treasury_reserved_per_cell[c] = 0	# legacy counter (kept if you still use it)
		if not treasury_reserved_per_cell_kind.has(c):
			treasury_reserved_per_cell_kind[c] = {}
		if not treasury_stack_kind.has(c):
			treasury_stack_kind[c] = ""			# unassigned
			
func get_inventory_totals() -> Dictionary:
	var out := {"rock": 0, "carrot": 0}
	for c in treasury_contents.keys():
		var bucket: Dictionary = treasury_contents[c]
		for k in bucket.keys():
			out[k] = int(out.get(k, 0)) + int(bucket[k])
	return out

func is_treasury_cell(cell: Vector2i) -> bool:
	return treasury_cells.has(cell)
	
func get_cell_inspect_text(cell: Vector2i) -> String:
	var gb: Dictionary = items_on_ground.get(cell, {})
	var g_rock := int(gb.get("rock", 0))
	var g_carrot := int(gb.get("carrot", 0))

	var s_rock := 0
	var s_carrot := 0
	if treasury_cells.has(cell):
		s_rock = _cell_stored_kind(cell, "rock")
		s_carrot = _cell_stored_kind(cell, "carrot")

	var stack_kind := _treasury_assigned_kind(cell) if treasury_cells.has(cell) else ""
	var area_id := int(treasury_cell_area_id.get(cell, -1))
	var parts := []
	if g_rock > 0 or g_carrot > 0:
		parts.append("Ground R:%d C:%d" % [g_rock, g_carrot])
	if s_rock > 0 or s_carrot > 0 or treasury_cells.has(cell):
		parts.append("Stored R:%d C:%d" % [s_rock, s_carrot])
	if stack_kind != "":
		parts.append("Stack:%s" % stack_kind)
	if area_id != -1:
		parts.append("Area:%d" % area_id)
	if parts.size() == 0:
		return "Empty"
	return " | ".join(parts)

func _area_allows(cell: Vector2i, kind: String) -> bool:
	var aid := int(treasury_cell_area_id.get(cell, -1))
	if aid == -1:
		return true
	var rule: Dictionary = treasury_area_rules.get(aid, {"any": true, "allowed": PackedStringArray()})
	if bool(rule.get("any", true)):
		return true
	var psa: PackedStringArray = rule.get("allowed", PackedStringArray())
	for s in psa:
		if String(s) == kind:
			return true
	return false

func get_treasury_rules_for_cell(cell: Vector2i) -> Dictionary:
	var aid := int(treasury_cell_area_id.get(cell, -1))
	if aid == -1:
		return {"any": true, "allowed": [] as Array[String]}
	var r: Dictionary = treasury_area_rules.get(aid, {"any": true, "allowed": PackedStringArray()})
	var psa: PackedStringArray = r.get("allowed", PackedStringArray())
	var arr: Array[String] = []
	for s in psa:
		arr.append(String(s))
	return {"any": bool(r.get("any", true)), "allowed": arr}

func _recompute_treasury_areas() -> void:
	_prev_cell_area_id = treasury_cell_area_id.duplicate()
	treasury_cell_area_id.clear()
	area_id_cells.clear()

	# flood fill across all treasury cells
	var seen := {}
	var area_next: int = 1
	for c in treasury_cells.keys():
		if seen.has(c):
			continue
		var cells := _treasury_area_from(c)
		for cc in cells:
			seen[cc] = true
			treasury_cell_area_id[cc] = area_next
		area_id_cells[area_next] = cells.duplicate()
		area_next += 1

	# carry over rules: for each new area, pick dominant previous area rules
	var new_rules := {}
	for aid in area_id_cells.keys():
		var cells2: Array[Vector2i] = area_id_cells[aid]
		var counts := {}
		for cc in cells2:
			var old := int(_prev_cell_area_id.get(cc, -1))
			if old != -1:
				counts[old] = int(counts.get(old, 0)) + 1
		var picked_old: int = -1
		var best := -1
		for k in counts.keys():
			var cnt := int(counts[k])
			if cnt > best:
				best = cnt
				picked_old = int(k)
		if picked_old != -1 and treasury_area_rules.has(picked_old):
			var oldr: Dictionary = treasury_area_rules[picked_old]
			var old_any: bool = bool(oldr.get("any", true))
			var old_psa: PackedStringArray = oldr.get("allowed", PackedStringArray())
			new_rules[aid] = {"any": old_any, "allowed": PackedStringArray(old_psa)}
		else:
			new_rules[aid] = {"any": true, "allowed": PackedStringArray()}
	treasury_area_rules = new_rules

func _enforce_area_rules(aid: int) -> void:
	var cells: Array[Vector2i] = area_id_cells.get(aid, [])
	if cells.size() == 0:
		return
	for cell in cells:
		if treasury_contents.has(cell):
			var bucket: Dictionary = treasury_contents[cell]
			for k in bucket.keys():
				var kind := String(k)
				var cnt := int(bucket[k])
				if cnt <= 0:
					continue
				var rule = treasury_area_rules.get(aid, {"any": true, "allowed": []})
				var any_allowed := bool(rule.get("any", true))
				var allowed_arr: Array = rule.get("allowed", [])
				var allowed := any_allowed or allowed_arr.has(kind)
				if not allowed:
					# spill to ground and queue hauls (they'll pick allowed areas)
					drop_item(cell, kind, cnt)
					bucket[kind] = 0
					for i in range(cnt):
						create_haul_job(cell, kind)
			treasury_contents[cell] = bucket
	_refresh_item_cell_visuals_for_area(aid)
	inventory_changed.emit()
	
func on_treasury_rules_changed_from_ui(cell: Vector2i, any_allowed: bool, allowed: Array[String]) -> void:
	var aid := int(treasury_cell_area_id.get(cell, -1))
	if aid == -1:
		return
	var psa := PackedStringArray()
	for s in allowed:
		psa.append(String(s))
	treasury_area_rules[aid] = {"any": any_allowed, "allowed": psa}
	_enforce_area_rules(aid)

func _refresh_item_cell_visuals_for_area(aid: int) -> void:
	var cells: Array[Vector2i] = area_id_cells.get(aid, [])
	for c in cells:
		_refresh_item_cell_visual(c)

#Water Helpers

func _bucket_capacity(cell: Vector2i) -> int:
	return bucket_capacity_per_bucket

func _bucket_stored(cell: Vector2i) -> int:
	return int(bucket_water.get(cell, 0))

func _bucket_reserved(cell: Vector2i) -> int:
	return int(bucket_reserved.get(cell, 0))

func _bucket_free_effective(cell: Vector2i) -> int:
	return _bucket_capacity(cell) - _bucket_stored(cell) - _bucket_reserved(cell)

func _reserve_bucket_cell(cell: Vector2i) -> void:
	bucket_reserved[cell] = _bucket_reserved(cell) + 1

func _release_bucket_cell(cell: Vector2i) -> void:
	bucket_reserved[cell] = max(0, _bucket_reserved(cell) - 1)

func _add_bucket_water(cell: Vector2i, count: int) -> void:
	bucket_water[cell] = _bucket_stored(cell) + count
	_refresh_item_cell_visual(cell)	# if you also draw water piles on that tile

func create_place_furniture_job(cell: Vector2i, kind: String) -> Job:
	# block if wall or already has furniture
	if walls_layer != null and walls_layer.get_cell_source_id(cell) != -1:
		return null
	if furniture_layer != null and furniture_layer.get_cell_source_id(cell) != -1:
		return null
	var j := Job.new()
	j.id = _next_id
	_next_id += 1
	j.type = "place_furniture"
	j.target_cell = cell
	j.data["furniture_kind"] = kind
	jobs.append(j)
	job_added.emit(j)
	return j

func ensure_place_furniture_job(cell: Vector2i, kind: String) -> void:
	if get_job_at(cell, "place_furniture") != null:
		return
	create_place_furniture_job(cell, kind)

func ensure_well_operate_job(well_cell: Vector2i) -> void:
	if get_job_at(well_cell, "well_operate") != null:
		return
	var j := Job.new()
	j.id = _next_id
	_next_id += 1
	j.type = "well_operate"
	j.target_cell = well_cell
	jobs.append(j)
	job_added.emit(j)

func ensure_haul_water_to_bucket(well_cell: Vector2i, bucket_cell: Vector2i) -> void:
	# produce generic haul job with kind "water" and deposit to bucket
	if not has_ground_item(well_cell, "water"):
		return
	var j := Job.new()
	j.id = _next_id
	_next_id += 1
	j.type = "haul_water"
	j.target_cell = well_cell
	j.data["kind"] = "water"
	j.data["count"] = 1
	j.data["deposit_cell"] = bucket_cell
	j.data["deposit_target"] = "bucket"
	jobs.append(j)
	job_added.emit(j)

func _ensure_water_supply_jobs() -> void:
	# for each bucket with free space, try to haul water; if none around, operate a well
	for bc in bucket_cells.keys():
		var bcell: Vector2i = bc
		if _bucket_free_effective(bcell) <= 0:
			continue
		print("Bucket ", bcell, " needs water (", _bucket_stored(bcell), "/", _bucket_capacity(bcell), ")")
		# first look for any well with water on ground
		var best_well: Vector2i = Vector2i.ZERO
		var found := false
		var best_steps := 0
		for wc in well_cells.keys():
			if has_ground_item(wc, "water"):
				var path = GridNav.find_path_cells(bcell, wc)
				if not path.is_empty():
					var steps = max(0, path.size() - 1)
					if not found or steps < best_steps:
						found = true
						best_steps = steps
						best_well = wc
		if found:
			# queue one haul if not already queued at that well cell
			if get_job_at(best_well, "haul_water") == null:
				ensure_haul_water_to_bucket(best_well, bcell)
			continue
		# otherwise, operate any reachable well to create water
		var picked := false
		for wc2 in well_cells.keys():
			var p2 = GridNav.find_path_cells(bcell, wc2)
			if not p2.is_empty():
				ensure_well_operate_job(wc2)
				picked = true
				break
		if not picked and well_cells.size() > 0:
			# as a fallback, operate the first well; hauling may follow later
			for wc3 in well_cells.keys():
				ensure_well_operate_job(wc3)
				break


func _treasury_assigned_kind(cell: Vector2i) -> String:
	return String(treasury_stack_kind.get(cell, ""))

func _cell_stored_kind(cell: Vector2i, kind: String) -> int:
	if not treasury_contents.has(cell):
		return 0
	return int((treasury_contents[cell] as Dictionary).get(kind, 0))

func _cell_reserved_kind(cell: Vector2i, kind: String) -> int:
	var bucket: Dictionary = treasury_reserved_per_cell_kind.get(cell, {})
	return int(bucket.get(kind, 0))

func _cell_free_effective_kind(cell: Vector2i, kind: String) -> int:
	var assigned: String = _treasury_assigned_kind(cell)
	if assigned != "" and assigned != kind:
		return 0
	if not _area_allows(cell, kind):
		return 0
	return _cell_capacity(cell) - _cell_stored_kind(cell, kind) - _cell_reserved_kind(cell, kind)

func _any_treasury_space_available_for(kind: String) -> bool:
	for k in treasury_cells.keys():
		if _cell_free_effective_kind(k, kind) > 0:
			return true
	return false


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

func _nearest_reachable_treasury_with_space_for(from_cell: Vector2i, kind: String) -> Variant:
	var found: bool = false
	var best_cell: Vector2i = Vector2i.ZERO
	var best_steps: int = 0
	for key in treasury_cells.keys():
		var tcell: Vector2i = key
		if _cell_free_effective_kind(tcell, kind) <= 0:
			continue
		var path: PackedVector2Array = GridNav.find_path_cells(from_cell, tcell)
		if path.is_empty():
			continue
		var steps: int = max(0, path.size() - 1)
		if not found or steps < best_steps:
			found = true
			best_steps = steps
			best_cell = tcell
	if found:
		return best_cell
	return null

func _reserve_treasury_cell(cell: Vector2i, kind: String) -> void:
	var bucket: Dictionary = treasury_reserved_per_cell_kind.get(cell, {})
	var cur: int = int(bucket.get(kind, 0))
	bucket[kind] = cur + 1
	treasury_reserved_per_cell_kind[cell] = bucket
	treasury_reserved += 1

func _release_treasury_cell(cell: Vector2i, kind: String) -> void:
	if treasury_reserved > 0:
		treasury_reserved -= 1
	var bucket: Dictionary = treasury_reserved_per_cell_kind.get(cell, {})
	var cur: int = int(bucket.get(kind, 0))
	bucket[kind] = max(0, cur - 1)
	treasury_reserved_per_cell_kind[cell] = bucket

func create_haul_job(cell: Vector2i, kind: String) -> Job:
	if not has_ground_item(cell, kind):
		return null
	var j: Job = Job.new()
	j.id = _next_id
	_next_id += 1
	j.type = "haul_" + kind
	j.target_cell = cell
	j.data["kind"] = kind
	j.data["count"] = 1
	jobs.append(j)
	job_added.emit(j)
	return j

func ensure_haul_job(cell: Vector2i, kind: String) -> void:
	if get_job_at(cell, "haul_" + kind) != null:
		return
	if has_ground_item(cell, kind):
		create_haul_job(cell, kind)

func remove_haul_job_at(cell: Vector2i) -> void:
	for j: Job in jobs:
		if j.target_cell == cell and j.type.begins_with("haul_") and (j.status == Job.Status.OPEN or j.status == Job.Status.RESERVED):
			cancel_job(j)
			return

func has_farm_harvest_job(cell: Vector2i) -> bool:
	return get_job_at(cell, "farm_harvest") != null

func ensure_farm_harvest_job(cell: Vector2i) -> void:
	if not has_farm_harvest_job(cell):
		var j: Job = Job.new()
		j.id = _next_id
		_next_id += 1
		j.type = "farm_harvest"
		j.target_cell = cell
		jobs.append(j)
		job_added.emit(j)

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
	_ensure_water_supply_jobs()

	for j: Job in jobs:
		if not j.is_open():
			continue

		# 1) operate well (stand next to it)
		if j.type == "well_operate":
			var adj = _find_reachable_adjacent(worker, j.target_cell)
			if adj == null:
				continue
			j.data["stand_cell"] = adj
			j.status = Job.Status.RESERVED
			j.reserved_by = worker.get_path()
			job_updated.emit(j)
			return j

		# 2) all hauls
		if j.type.begins_with("haul_"):
			var kind: String = String(j.data.get("kind", "rock"))

			var start_cell := GridNav.world_to_cell(worker.global_position, floor_layer)
			var path_to_item = GridNav.find_path_cells(start_cell, j.target_cell)
			if path_to_item.is_empty():
				continue

			# DO NOT reserve unless the item actually exists
			if not has_ground_item(j.target_cell, kind):
				continue

			# bucket-targeted haul (water)
			if j.data.has("deposit_target") and String(j.data["deposit_target"]) == "bucket":
				var depot_cell: Vector2i = j.data.get("deposit_cell", Vector2i.ZERO)
				if _bucket_free_effective(depot_cell) <= 0:
					continue
				j.status = Job.Status.RESERVED
				j.reserved_by = worker.get_path()
				_reserve_bucket_cell(depot_cell)
				job_updated.emit(j)
				return j

			# treasury haul (rock/carrot)
			var depot_variant = find_best_deposit_cell_for_item(j.target_cell, kind)
			if depot_variant == null:
				continue
			var depot_cell2: Vector2i = depot_variant as Vector2i
			j.data["deposit_cell"] = depot_cell2
			j.status = Job.Status.RESERVED
			j.reserved_by = worker.get_path()
			_reserve_treasury_cell(depot_cell2, kind)
			job_updated.emit(j)
			return j

		# 3) everything else (dig/build/rooms/farm)
		var adj2 = _find_reachable_adjacent(worker, j.target_cell)
		if adj2 != null:
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
		var kind: String = job.data.get("room_kind", "treasury")
		if kind == "treasury":
			_ensure_room_tile_defaults("treasury")
			if room_treasury_source_id == -1:
				push_error("JobManager: room_treasury_source_id not set and no sample room tile found.")
			else:
				rooms_layer.set_cell(job.target_cell, room_treasury_source_id, room_treasury_atlas_coords, room_treasury_alt)
				treasury_cells[job.target_cell] = true

				if not treasury_contents.has(job.target_cell):
					treasury_contents[job.target_cell] = {"rock": 0, "carrot": 0}
				if not treasury_reserved_per_cell.has(job.target_cell):
					treasury_reserved_per_cell[job.target_cell] = 0
				_refresh_item_cell_visual(job.target_cell)
				treasury_stack_kind[job.target_cell] = ""
				_recompute_treasury_areas()

				# housekeeping: sweep existing rocks under this new treasury
				var ground_here: int = 0
				if items_on_ground.has(job.target_cell):
					var bucket_here: Dictionary = items_on_ground[job.target_cell]
					ground_here = int(bucket_here.get("rock", 0))
				if ground_here > 0:
					var area: Array[Vector2i] = _treasury_area_from(job.target_cell)
					var free_total: int = 0
					for cell_in_area: Vector2i in area:
						free_total += max(0, _cell_free_effective(cell_in_area))
					var to_queue: int = min(ground_here, free_total)
					for i in range(to_queue):
						create_haul_job(job.target_cell, "rock")
		else:
			# FARM
			if room_farm_source_id == -1:
				# fallback to treasury tile if you haven't set a farm tile yet
				rooms_layer.set_cell(job.target_cell, room_treasury_source_id, room_treasury_atlas_coords, room_treasury_alt)
			else:
				rooms_layer.set_cell(job.target_cell, room_farm_source_id, room_farm_atlas_coords, room_farm_alt)
			FarmSystem.add_plot(job.target_cell)


	elif job.type == "unassign_room":
		if rooms_layer != null:
			# remove the room tile first
			rooms_layer.erase_cell(job.target_cell)

			# spill EVERYTHING stored on this treasury cell back onto the ground
			if treasury_contents.has(job.target_cell):
				var bucket: Dictionary = treasury_contents[job.target_cell]
				for k in bucket.keys():
					var cnt: int = int(bucket[k])
					if cnt > 0:
						drop_item(job.target_cell, String(k), cnt)
						bucket[k] = 0
						inventory_changed.emit()

				treasury_contents[job.target_cell] = bucket

			# clean up all treasury maps for this cell
			treasury_cells.erase(job.target_cell)
			treasury_reserved_per_cell.erase(job.target_cell)
			treasury_reserved_per_cell_kind.erase(job.target_cell)
			treasury_stack_kind.erase(job.target_cell)

			# if you support farms on this tile too, remove the plot
			FarmSystem.remove_plot(job.target_cell)

			# redraw items layer for this cell after spilling
			_refresh_item_cell_visual(job.target_cell)
			_recompute_treasury_areas()

	elif job.type.begins_with("haul_"):
		var kind: String = String(job.data.get("kind", "rock"))

		# --- BUCKET deliveries ---
		if job.data.has("deposit_target") and String(job.data["deposit_target"]) == "bucket":
			var depot_cell_b: Vector2i = job.data["deposit_cell"] as Vector2i
			_release_bucket_cell(depot_cell_b)
			_add_bucket_water(depot_cell_b, int(job.data.get("count", 1)))
			job.status = Job.Status.DONE
			job_completed.emit(job)
			return	# IMPORTANT

		# --- TREASURY deliveries ---
		if job.data.has("deposit_cell"):
			var depot_cell: Vector2i = job.data["deposit_cell"] as Vector2i
			_release_treasury_cell(depot_cell, kind)
			if _treasury_assigned_kind(depot_cell) == "":
				treasury_stack_kind[depot_cell] = kind
			_add_treasury_item(depot_cell, kind, int(job.data.get("count", 1)))
		else:
			var depot = find_best_deposit_cell_for_item(job.target_cell, kind)
			if depot != null:
				var dc: Vector2i = depot as Vector2i
				if _treasury_assigned_kind(dc) == "":
					treasury_stack_kind[dc] = kind
				_add_treasury_item(dc, kind, int(job.data.get("count", 1)))


	elif job.type == "farm_harvest":
		var drop: int = FarmSystem.on_harvest_completed(job.target_cell)	# now 1 or 2 based on auto_replant
		if drop > 0:
			drop_item(job.target_cell, "carrot", drop)
			for i in range(drop):
				create_haul_job(job.target_cell, "carrot")
				
	elif job.type == "place_furniture":
		var kind: String = String(job.data.get("furniture_kind", "well"))
		if furniture_layer == null:
			push_error("JobManager: furniture_layer not set")
		else:
			if kind == "well":
				if well_source_id != -1:
					furniture_layer.set_cell(job.target_cell, well_source_id, well_atlas_coords, well_alt)
					well_cells[job.target_cell] = true
			elif kind == "bucket":
				if bucket_source_id != -1:
					furniture_layer.set_cell(job.target_cell, bucket_source_id, bucket_atlas_coords, bucket_alt)
					bucket_cells[job.target_cell] = true
					bucket_water[job.target_cell] = 0
					bucket_reserved[job.target_cell] = 0

	elif job.type == "well_operate":
		# doing task: produce 1 water on the well cell
		drop_item(job.target_cell, "water", 1)
		# try to immediately queue a haul to the nearest needy bucket
		for bc in bucket_cells.keys():
			if _bucket_free_effective(bc) > 0:
				ensure_haul_water_to_bucket(job.target_cell, bc)
				break

	job.status = Job.Status.DONE
	job_completed.emit(job)

func _nearest_reachable_treasury_with_space(from_cell: Vector2i) -> Variant:
	var found: bool = false
	var best_cell: Vector2i = Vector2i.ZERO
	var best_steps: int = 0
	for key in treasury_cells.keys():
		var tcell: Vector2i = key
		if _cell_free_effective(tcell) <= 0:
			continue
		var path: PackedVector2Array = GridNav.find_path_cells(from_cell, tcell)
		if path.is_empty():
			continue
		var steps: int = max(0, path.size() - 1)
		if not found or steps < best_steps:
			found = true
			best_steps = steps
			best_cell = tcell
	if found:
		return best_cell
	return null

func _treasury_area_from(seed: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var q: Array[Vector2i] = []
	var seen := {}
	if not treasury_cells.has(seed):
		return out
	q.append(seed)
	seen[seed] = true
	while q.size() > 0:
		var c: Vector2i = q.pop_front()
		out.append(c)
		for d: Vector2i in DIR4:
			var n: Vector2i = c + d
			if treasury_cells.has(n) and not seen.has(n):
				seen[n] = true
				q.append(n)
	return out

func find_best_deposit_cell_for_item(from_cell: Vector2i, kind: String) -> Variant:
	var seed_variant = _nearest_reachable_treasury_with_space_for(from_cell, kind)
	if seed_variant == null:
		return null
	var seed: Vector2i = seed_variant as Vector2i
	var area: Array[Vector2i] = _treasury_area_from(seed)

	# 1) nearest partially-filled stack of this kind
	var found: bool = false
	var best_cell: Vector2i = Vector2i.ZERO
	var best_steps: int = 0
	for cell: Vector2i in area:
		if _cell_stored_kind(cell, kind) <= 0:
			continue
		if _cell_free_effective_kind(cell, kind) <= 0:
			continue
		var path1: PackedVector2Array = GridNav.find_path_cells(from_cell, cell)
		if path1.is_empty():
			continue
		var steps1: int = max(0, path1.size() - 1)
		if not found or steps1 < best_steps:
			found = true
			best_steps = steps1
			best_cell = cell
	if found:
		return best_cell

	# 2) nearest eligible empty/unassigned cell
	found = false
	for cell2: Vector2i in area:
		if _cell_free_effective_kind(cell2, kind) <= 0:
			continue
		var path2: PackedVector2Array = GridNav.find_path_cells(from_cell, cell2)
		if path2.is_empty():
			continue
		var steps2: int = max(0, path2.size() - 1)
		if not found or steps2 < best_steps:
			found = true
			best_steps = steps2
			best_cell = cell2
	if found:
		return best_cell

	# 3) global fallback (kind-aware)
	return _nearest_reachable_treasury_with_space_for(from_cell, kind)

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
	if job.type.begins_with("haul_") and job.data.has("deposit_cell"):
		if job.data.has("deposit_target") and String(job.data["deposit_target"]) == "bucket":
			_release_bucket_cell(job.data["deposit_cell"] as Vector2i)
		else:
			var kind: String = String(job.data.get("kind", "rock"))
			_release_treasury_cell(job.data["deposit_cell"] as Vector2i, kind)
		job.data.erase("deposit_cell")
	job.status = Job.Status.OPEN
	job.reserved_by = NodePath("")
	job_updated.emit(job)

func cancel_job(job: Job) -> void:
	if job == null:
		return
	if job.type.begins_with("haul_") and job.data.has("deposit_cell"):
		if job.data.has("deposit_target") and String(job.data["deposit_target"]) == "bucket":
			_release_bucket_cell(job.data["deposit_cell"] as Vector2i)
		else:
			var kind: String = String(job.data.get("kind", "rock"))
			_release_treasury_cell(job.data["deposit_cell"] as Vector2i, kind)
		job.data.erase("deposit_cell")
	job.status = Job.Status.CANCELLED
	job_updated.emit(job)

func _refresh_item_cell_visual(cell: Vector2i) -> void:
	if items_layer == null:
		return

	var show_kind: String = ""
	var total: int = 0

	if treasury_cells.has(cell):
		var assigned: String = _treasury_assigned_kind(cell)
		if assigned != "":
			# show the assigned stack only
			total = _cell_stored_kind(cell, assigned)
			# optionally include ground of same kind for continuity
			var ground_bucket: Dictionary = items_on_ground.get(cell, {})
			total += int(ground_bucket.get(assigned, 0))
			show_kind = assigned
		else:
			# unassigned treasury: show whichever stored kind is non-zero (if any)
			var bucket: Dictionary = treasury_contents.get(cell, {})
			for k in bucket.keys():
				var cnt: int = int(bucket[k])
				if cnt > 0:
					show_kind = String(k)
					total = cnt
					break
			if show_kind == "":
				# fall back to ground items (pick largest)
				var gb: Dictionary = items_on_ground.get(cell, {})
				var best_cnt: int = 0
				for gk in gb.keys():
					var c: int = int(gb[gk])
					if c > best_cnt:
						best_cnt = c
						show_kind = String(gk)
				total = best_cnt
	else:
		# non-treasury: pick the largest pile visually (ground only + any stored just in case)
		var gb2: Dictionary = items_on_ground.get(cell, {})
		var best2: int = 0
		for gk2 in gb2.keys():
			var c2: int = int(gb2[gk2])
			if c2 > best2:
				best2 = c2
				show_kind = String(gk2)
		total = best2

	if total <= 0 or show_kind == "":
		items_layer.erase_cell(cell)
		return

	if show_kind == "rock":
		if rock_source_id == -1:
			return
		var idx_r: int = _index_for_count(total, rock_stack_max_per_cell)
		var atlas_r: Vector2i = [rock_atlas_coords_0, rock_atlas_coords_1, rock_atlas_coords_2, rock_atlas_coords_3][idx_r]
		items_layer.set_cell(cell, rock_source_id, atlas_r, rock_alt)
	elif show_kind == "carrot":
		if carrot_source_id == -1:
			return
		var idx_c: int = _index_for_count(total, carrot_stack_max_per_cell)
		var atlas_c: Vector2i = [carrot_atlas_coords_0, carrot_atlas_coords_1, carrot_atlas_coords_2, carrot_atlas_coords_3][idx_c]
		items_layer.set_cell(cell, carrot_source_id, atlas_c, carrot_alt)

func _index_for_count(count: int, max_per_cell: int) -> int:
	var maxv: int = max(1, max_per_cell)
	var r: float = float(count) / float(maxv)
	if r <= 0.25:
		return 0
	elif r <= 0.5:
		return 1
	elif r <= 0.75:
		return 2
	else:
		return 3


func _add_treasury_item(cell: Vector2i, kind: String, count: int) -> void:
	if not treasury_contents.has(cell):
		treasury_contents[cell] = {}
	var bucket: Dictionary = treasury_contents[cell]
	var cur: int = int(bucket.get(kind, 0))
	bucket[kind] = cur + count
	treasury_contents[cell] = bucket
	inventory_changed.emit()
	_refresh_item_cell_visual(cell)


func create_haul_job_to(source_cell: Vector2i, kind: String, deposit_cell: Vector2i) -> Job:
	if not has_ground_item(source_cell, kind):
		return null
	if not treasury_cells.has(deposit_cell):
		return null
	var j: Job = Job.new()
	j.id = _next_id
	_next_id += 1
	j.type = "haul_rock"
	j.target_cell = source_cell
	j.data["kind"] = kind
	j.data["count"] = 1
	j.data["deposit_cell"] = deposit_cell
	jobs.append(j)
	job_added.emit(j)
	return j

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
