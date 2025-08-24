extends Node

# ===== Signals kept for compatibility =====
signal job_added(job: Job)
signal job_updated(job: Job)
signal job_completed(job: Job)
signal items_changed(cell: Vector2i)      # re-emitted from GroundItems
signal inventory_changed()                # re-emitted from Inventory

# ===== Tiles / Layers (same as before) =====
@export var build_wall_source_id: int = 0
@export var build_wall_atlas_coords: Vector2i = Vector2i(3, 11)
@export var build_wall_alternative_tile: int = 0

var floor_layer: TileMapLayer
var walls_layer: TileMapLayer
var rooms_layer: TileMapLayer
var furniture_layer: TileMapLayer
var items_layer: TileMapLayer

const DIR4 := [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]

# ===== Treasury / Inventory visuals config (unchanged) =====
@export var treasury_capacity_per_tile: int = 10

# rock visuals
@export var rock_stack_max_per_cell: int = 12
@export var rock_source_id: int = -1
@export var rock_atlas_coords_0: Vector2i = Vector2i.ZERO
@export var rock_atlas_coords_1: Vector2i = Vector2i.ZERO
@export var rock_atlas_coords_2: Vector2i = Vector2i.ZERO
@export var rock_atlas_coords_3: Vector2i = Vector2i.ZERO
@export var rock_alt: int = 0

# carrots visuals
@export var carrot_stack_max_per_cell: int = 12
@export var carrot_source_id: int = -1
@export var carrot_atlas_coords_0: Vector2i = Vector2i.ZERO
@export var carrot_atlas_coords_1: Vector2i = Vector2i.ZERO
@export var carrot_atlas_coords_2: Vector2i = Vector2i.ZERO
@export var carrot_atlas_coords_3: Vector2i = Vector2i.ZERO
@export var carrot_alt: int = 0

# rooms tiles
@export var room_treasury_source_id: int = -1
@export var room_treasury_atlas_coords: Vector2i = Vector2i.ZERO
@export var room_treasury_alt: int = 0

@export var room_farm_source_id: int = 1
@export var room_farm_atlas_coords: Vector2i = Vector2i(50,17)
@export var room_farm_alt: int = 0

# furniture tiles
@export var well_source_id: int = 0
@export var well_atlas_coords: Vector2i = Vector2i(38,16)
@export var well_alt: int = 0

@export var bucket_source_id: int = 0
@export var bucket_atlas_coords: Vector2i = Vector2i(37,16)
@export var bucket_alt: int = 0

# ===== Jobs =====
var jobs: Array[Job] = []
var _next_id: int = 1
var treasury_reserved_legacy: int = 0   # kept for HUD compatibility if you used it

# ===== Init =====
func _ready() -> void:
	# Dev UI hook for rules
	if Inventory != null:
		Inventory.cell_changed.connect(func(c: Vector2i) -> void:
			_refresh_item_cell_visual(c)
		)
		Inventory.area_changed.connect(func(cs: Array[Vector2i]) -> void:
			for c in cs:
				_refresh_item_cell_visual(c)
		)
		
	var ui := get_node_or_null("/root/DevUI")
	if ui != null:
		ui.treasury_rules_changed.connect(on_treasury_rules_changed_from_ui)

	# Re-emit signals for existing listeners
	GroundItems.items_changed.connect(_on_ground_items_changed)
	Inventory.inventory_changed.connect(func(): inventory_changed.emit())
	Inventory.spill_items.connect(_on_inventory_spill_items)

func init(floor: TileMapLayer, walls: TileMapLayer, rooms: TileMapLayer, furniture: TileMapLayer, items: TileMapLayer) -> void:
	floor_layer = floor
	walls_layer = walls
	rooms_layer = rooms
	furniture_layer = furniture
	items_layer = items

	Inventory.init(rooms_layer, treasury_capacity_per_tile)
	WaterSystem.init(furniture_layer)
	_bootstrap_preplaced_rooms()
	treasury_reserved_legacy = 0


# ===== Public small helpers you already use =====
func _bootstrap_preplaced_rooms() -> void:
	if rooms_layer == null: return
	var used := rooms_layer.get_used_cells()
	for c in used:
		var sid := rooms_layer.get_cell_source_id(c)
		var at  := rooms_layer.get_cell_atlas_coords(c)
		var alt := 0
		if rooms_layer.has_method("get_cell_alternative_tile"):
			alt = rooms_layer.get_cell_alternative_tile(c)

		# Treasury
		if sid == room_treasury_source_id and at == room_treasury_atlas_coords and alt == room_treasury_alt:
			Inventory.on_assign_treasury_cell(c)
			_refresh_item_cell_visual(c)

		# Farms
		elif sid == room_farm_source_id and at == room_farm_atlas_coords and alt == room_farm_alt:
			FarmSystem.add_plot(c)
			WaterSystem.request_one_shot_water_to_farm(c)

func _on_inventory_changed() -> void:
	# Refresh every known treasury cell sprite (cheap at your current scale).
	for c in Inventory.contents.keys():
		_refresh_item_cell_visual(c)

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

func get_inventory_totals() -> Dictionary:
	return Inventory.get_inventory_totals()

func is_treasury_cell(cell: Vector2i) -> bool:
	return Inventory.is_treasury_cell(cell)

func get_cell_inspect_text(cell: Vector2i) -> String:
	var g_rock := GroundItems.count(cell, "rock")
	var g_carrot := GroundItems.count(cell, "carrot")
	var s_rock := Inventory.get_stored(cell, "rock")
	var s_carrot := Inventory.get_stored(cell, "carrot")
	var stack := Inventory.get_assigned_kind(cell) if Inventory.is_treasury_cell(cell) else ""
	var parts := []
	if g_rock > 0 or g_carrot > 0:
		parts.append("Ground R:%d C:%d" % [g_rock, g_carrot])
	if s_rock > 0 or s_carrot > 0 or Inventory.is_treasury_cell(cell):
		parts.append("Stored R:%d C:%d" % [s_rock, s_carrot])
	if stack != "":
		parts.append("Stack:%s" % stack)
	return " | ".join(parts) if parts.size() > 0 else "Empty"

# ===== Rules UI passthrough =====
func get_treasury_rules_for_cell(cell: Vector2i) -> Dictionary:
	return Inventory.get_rules_for_cell(cell)

func on_treasury_rules_changed_from_ui(cell: Vector2i, any_allowed: bool, allowed: Array[String]) -> void:
	Inventory.set_rules_for_cell(cell, any_allowed, allowed)

# ===== Ground items passthrough (keep old signatures) =====
func drop_item(cell: Vector2i, kind: String, count: int) -> void:
	GroundItems.drop_item(cell, kind, count)

func has_ground_item(cell: Vector2i, kind: String) -> bool:
	return GroundItems.has(cell, kind)

func take_item(cell: Vector2i, kind: String, count: int) -> bool:
	return GroundItems.take(cell, kind, count)

func _on_ground_items_changed(cell: Vector2i, _kind: String) -> void:
	_refresh_item_cell_visual(cell)
	items_changed.emit(cell)

# ===== Job Factory ============================================================
func create_job(type: String, cell: Vector2i, data: Dictionary = {}) -> Job:
	var j := Job.new()
	j.id = _next_id
	_next_id += 1
	j.type = type
	j.target_cell = cell
	j.data = data
	jobs.append(j)
	job_added.emit(j)
	return j

# shorthand you were using
func create_haul_job(cell: Vector2i, kind: String) -> Job:
	# Never create generic water hauls; WaterSystem will issue targeted ones.
	if kind == "water":
		return null
	if not has_ground_item(cell, kind):
		return null
	return create_job("haul_" + kind, cell, {"kind": kind, "count": 1})

func ensure_haul_job(cell: Vector2i, kind: String) -> void:
	if get_job_at(cell, "haul_" + kind) != null: return
	if has_ground_item(cell, kind):
		create_haul_job(cell, kind)

# ===== Request / Start / Complete ============================================
func request_job(worker: Node2D) -> Job:
	WaterSystem.ensure_supply_jobs()

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

		# 2) haul jobs
		if j.type.begins_with("haul_"):
			var kind := String(j.data.get("kind", "rock"))
			var start_cell := GridNav.world_to_cell(worker.global_position, floor_layer)
			var path_to_pickup = GridNav.find_path_cells(start_cell, j.target_cell)
			if path_to_pickup.is_empty():
				continue

			# 2a) WATER from BUCKET (no ground item needed)
			# 2a) WATER f	rom BUCKET (no ground item needed)
			if kind == "water" and String(j.data.get("source", "")) == "bucket":
				# If the withdraw was already reserved at job creation, just take the job.
				if bool(j.data.get("withdraw_reserved", false)):
					j.status = Job.Status.RESERVED
					j.reserved_by = worker.get_path()
					job_updated.emit(j)
					return j

				# Legacy/older jobs: try to reserve now (authoritative). No has_bucket_water gate.
				if not WaterSystem.reserve_bucket_withdraw(j.target_cell):
					# Stale / bucket drained / someone else took it.
					# If this was for a farm, free the farm and retry next frame.
					if j.data.has("deposit_target") and String(j.data["deposit_target"]) == "farm" and j.data.has("deposit_cell"):
						var fcell: Vector2i = j.data["deposit_cell"]
						WaterSystem.clear_pending_for_farm(fcell)
						WaterSystem.call_deferred("request_one_shot_water_to_farm", fcell)
					cancel_job(j)
					continue

				# Mark and hand it out.
				j.data["withdraw_reserved"] = true
				j.status = Job.Status.RESERVED
				j.reserved_by = worker.get_path()
				job_updated.emit(j)
				return j




			# 2b) everything else must exist on ground at pickup
			if not has_ground_item(j.target_cell, kind):
				continue

			# 2c) water -> BUCKET (delivery target bucket must have space)
			if j.data.has("deposit_target") and String(j.data["deposit_target"]) == "bucket":
				var bcell: Vector2i = j.data.get("deposit_cell", Vector2i.ZERO)
				if WaterSystem.bucket_free_effective(bcell) <= 0:
					continue

				# If this is water-from-ground, reserve one unit from the well pile now.
				if kind == "water" and String(j.data.get("source","")) == "ground":
					if not WaterSystem.reserve_pile(j.target_cell):
						continue
					j.data["pile_reserved"] = true

				j.status = Job.Status.RESERVED
				j.reserved_by = worker.get_path()
				WaterSystem.reserve_bucket(bcell)  # receiving bucket slot

				# optional: show "incoming" at bucket
				_refresh_item_cell_visual(bcell)
				items_changed.emit(bcell)

				job_updated.emit(j)
				return j

			# 2d) water -> FARM
			if j.data.has("deposit_target") and String(j.data["deposit_target"]) == "farm":
				# If this is water-from-ground, reserve one unit from the well pile now.
				if kind == "water" and String(j.data.get("source","")) == "ground":
					if not WaterSystem.reserve_pile(j.target_cell):
						# The puddle exists but all units are already reserved by others.
						# -> free the farm so it can re-evaluate next frame (bucket, other well, or wait).
						if j.data.has("deposit_cell"):
							var fcell: Vector2i = j.data["deposit_cell"]
							WaterSystem.clear_pending_for_farm(fcell)
							# IMPORTANT: defer the re-request to avoid job-loop thrash in this same call
							WaterSystem.call_deferred("request_one_shot_water_to_farm", fcell)
						cancel_job(j)
						continue
					j.data["pile_reserved"] = true

				j.status = Job.Status.RESERVED
				j.reserved_by = worker.get_path()
				job_updated.emit(j)
				return j



			# 2e) inventory hauls (rock/carrot) -> pick best treasury cell  (non-water only)
			if kind == "water":
				continue
			var depot = _pick_allowed_deposit_cell(kind, j.target_cell)
			if depot == null:
				continue
			var dc: Vector2i = depot
			j.data["deposit_cell"] = dc
			j.data["deposit_reserved"] = true
			j.status = Job.Status.RESERVED
			j.reserved_by = worker.get_path()
			Inventory.reserve_cell(dc, kind)
			job_updated.emit(j)
			return j


		# 3) dig/build/room/farm jobs that need adjacent stand cell
		var adj2 = _find_reachable_adjacent(worker, j.target_cell)
		if adj2 != null:
			j.status = Job.Status.RESERVED
			j.reserved_by = worker.get_path()
			job_updated.emit(j)
			return j

	return null


func start_job(job: Job) -> void:
	if job == null: return
	job.status = Job.Status.ACTIVE
	job_updated.emit(job)

func complete_job(job: Job) -> void:
	if job == null: return

	if job.type == "dig_wall":
		if walls_layer != null:
			walls_layer.erase_cell(job.target_cell)
		GridNav.astar.set_point_solid(job.target_cell, false)
		drop_item(job.target_cell, "rock", 1)

	elif job.type == "build_wall":
		_ensure_build_tile_defaults()
		if _is_cell_occupied_by_worker(job.target_cell):
			job.status = Job.Status.OPEN
			job.reserved_by = NodePath("")
			job_updated.emit(job)
			return
		if build_wall_source_id == -1:
			push_error("JobManager: build_wall_source_id not set.")
		else:
			walls_layer.set_cell(job.target_cell, build_wall_source_id, build_wall_atlas_coords, build_wall_alternative_tile)
			GridNav.astar.set_point_solid(job.target_cell, true)

	elif job.type == "assign_room":
		var kind := String(job.data.get("room_kind", "treasury"))
		if kind == "treasury":
			_ensure_room_tile_defaults("treasury")
			if room_treasury_source_id == -1:
				push_error("JobManager: room_treasury_source_id not set.")
			else:
				rooms_layer.set_cell(job.target_cell, room_treasury_source_id, room_treasury_atlas_coords, room_treasury_alt)
				Inventory.on_assign_treasury_cell(job.target_cell)
				_refresh_item_cell_visual(job.target_cell)
				# housekeeping: sweep rocks already under this new treasury (limited by area free space)
				var ground_rocks := GroundItems.count(job.target_cell, "rock")
				if ground_rocks > 0:
					var area: Array[Vector2i] = Inventory.area_cells_for(job.target_cell)
					var free_total := 0
					for c in area:
						free_total += max(0, Inventory.cell_free_effective_for(c, "rock"))
					var to_queue = min(ground_rocks, free_total)
					for i in range(to_queue):
						create_haul_job(job.target_cell, "rock")
		else:
			# FARM room
			if room_farm_source_id == -1:
				rooms_layer.set_cell(job.target_cell, room_treasury_source_id, room_treasury_atlas_coords, room_treasury_alt)
			else:
				rooms_layer.set_cell(job.target_cell, room_farm_source_id, room_farm_atlas_coords, room_farm_alt)
			FarmSystem.add_plot(job.target_cell)
			WaterSystem.request_one_shot_water_to_farm(job.target_cell)

	elif job.type == "unassign_room":
		if rooms_layer != null:
			rooms_layer.erase_cell(job.target_cell)
			Inventory.on_unassign_treasury_cell(job.target_cell)
			FarmSystem.remove_plot(job.target_cell)
			_refresh_item_cell_visual(job.target_cell)

	elif job.type.begins_with("haul_"):
		var kind := String(job.data.get("kind", "rock"))

		# Release well-pile reservation if this was water-from-ground
		if kind == "water" and String(job.data.get("source","")) == "ground":
			if bool(job.data.get("pile_reserved", false)):
				WaterSystem.release_pile(job.target_cell)
				job.data.erase("pile_reserved")

		# --- deliver to BUCKET (handle before any generic deposit) ---
		if job.data.has("deposit_target") and String(job.data["deposit_target"]) == "bucket":
			if job.data.has("deposit_cell"):
				var bcell: Vector2i = job.data["deposit_cell"]
				WaterSystem.release_bucket(bcell)
				WaterSystem.add_bucket_water(bcell, int(job.data.get("count", 1)))
				WaterSystem.clear_pending_for_bucket(bcell)
			job.status = Job.Status.DONE
			job_completed.emit(job)
			return

		# --- deliver to FARM (handle before any generic deposit) ---
		if job.data.has("deposit_target") and String(job.data["deposit_target"]) == "farm":
			if job.data.has("deposit_cell"):
				var fcell: Vector2i = job.data["deposit_cell"]
				FarmSystem.on_water_delivered(fcell)
				WaterSystem.clear_pending_for_farm(fcell)
			job.status = Job.Status.DONE
			job_completed.emit(job)
			return

		# --- inventory deliveries (non-water only) ---
		if job.data.has("deposit_cell") and kind != "water":
			var dc: Vector2i = job.data["deposit_cell"]

			# Release reservation first so capacity check is truthful
			Inventory.release_cell(dc, kind)

			var allowed := _is_allowed_in_cell_for(dc, kind)
			var free := Inventory.cell_free_effective_for(dc, kind)
			if (not allowed) or free <= 0:
				# Can't place here now (rules changed or it's actually full):
				# drop on ground and queue a sweep (non-water only).
				drop_item(dc, kind, 1)
				ensure_haul_job(dc, kind)   # create_haul_job ignores "water"
				_refresh_item_cell_visual(dc)
				job.status = Job.Status.DONE
				job_completed.emit(job)
				return

			# Happy path: deposit to inventory
			if Inventory.get_assigned_kind(dc) == "":
				Inventory.stack_kind[dc] = kind
			Inventory.add_item(dc, kind, int(job.data.get("count", 1)))
			_refresh_item_cell_visual(dc)
			job.status = Job.Status.DONE
			job_completed.emit(job)
			return

		# --- fallback: try to pick a deposit now (non-water only) ---
		if kind != "water":
			var dp = _pick_allowed_deposit_cell(kind, job.target_cell)
			if dp != null:
				var dc2: Vector2i = dp
				if Inventory.get_assigned_kind(dc2) == "":
					Inventory.stack_kind[dc2] = kind
				Inventory.add_item(dc2, kind, int(job.data.get("count", 1)))
				_refresh_item_cell_visual(dc2)
				job.status = Job.Status.DONE
				job_completed.emit(job)
				return

		# No valid inventory target (or this was water with no target):
		# drop at pickup cell; WaterSystem will re-evaluate as needed.
		drop_item(job.target_cell, kind, int(job.data.get("count", 1)))
		job.status = Job.Status.DONE
		job_completed.emit(job)
		return

	elif job.type == "farm_harvest":
		var drop := FarmSystem.on_harvest_completed(job.target_cell) # 1 or 2 depending on auto_replant
		if drop > 0:
			drop_item(job.target_cell, "carrot", drop)
			for i in range(drop):
				create_haul_job(job.target_cell, "carrot")

	elif job.type == "place_furniture":
		var fk := String(job.data.get("furniture_kind", "well"))
		if furniture_layer == null:
			push_error("JobManager: furniture_layer not set")
		else:
			if fk == "well" and well_source_id != -1:
				furniture_layer.set_cell(job.target_cell, well_source_id, well_atlas_coords, well_alt)
				GridNav.astar.set_point_solid(job.target_cell, false)
			elif fk == "bucket" and bucket_source_id != -1:
				furniture_layer.set_cell(job.target_cell, bucket_source_id, bucket_atlas_coords, bucket_alt)
			WaterSystem.on_place_furniture(job.target_cell, fk)

	elif job.type == "well_operate":
		WaterSystem.on_well_operate_completed(job.target_cell)

	job.status = Job.Status.DONE
	job_completed.emit(job)

# inventory spill handler -> drop to ground + queue hauls
func _on_inventory_spill_items(cell: Vector2i, kind: String, count: int) -> void:
	if count <= 0: return

	# If the spill happened *inside a treasury*, try to re-home it immediately
	if Inventory.is_treasury_cell(cell):
		var remain := count
		var area: Array[Vector2i] = Inventory.area_cells_for(cell)

		# First pass: fill existing stacks of the same kind
		for c in area:
			if c == cell: continue
			if Inventory.get_stored(c, kind) <= 0: continue
			var free = max(0, Inventory.cell_free_effective_for(c, kind))
			if free <= 0: continue
			var put = min(free, remain)
			if put > 0:
				if Inventory.get_assigned_kind(c) == "":
					Inventory.stack_kind[c] = kind
				Inventory.add_item(c, kind, put)
				_refresh_item_cell_visual(c)
				remain -= put
			if remain <= 0:
				break

		# Second pass: use empty/unassigned slots
		if remain > 0:
			for c2 in area:
				if c2 == cell: continue
				var free2 = max(0, Inventory.cell_free_effective_for(c2, kind))
				if free2 <= 0: continue
				var put2 = min(free2, remain)
				if put2 > 0:
					if Inventory.get_assigned_kind(c2) == "":
						Inventory.stack_kind[c2] = kind
					Inventory.add_item(c2, kind, put2)
					_refresh_item_cell_visual(c2)
					remain -= put2
				if remain <= 0:
					break

		# Only spill leftovers to ground and queue sweeps
		if remain > 0:
			drop_item(cell, kind, remain)
			for i in range(remain):
				create_haul_job(cell, kind)
		return

	# Non-treasury spills: original behavior
	drop_item(cell, kind, count)
	for i in range(count):
		create_haul_job(cell, kind)

# ===== Job utils ==============================================================
func get_job_at(cell: Vector2i, type: String) -> Job:
	for j: Job in jobs:
		if (j.status != Job.Status.DONE and j.status != Job.Status.CANCELLED) and j.type == type and j.target_cell == cell:
			return j
	return null

func has_job_at(cell: Vector2i, type: String) -> bool:
	return get_job_at(cell, type) != null

func remove_haul_job_at(cell: Vector2i) -> void:
	for j: Job in jobs:
		if j.target_cell == cell and j.type.begins_with("haul_") and (j.status == Job.Status.OPEN or j.status == Job.Status.RESERVED):
			cancel_job(j)
			return

# room jobs
func create_assign_room_job(cell: Vector2i, room_kind: String) -> Job:
	if rooms_layer == null: return null
	if walls_layer != null and walls_layer.get_cell_source_id(cell) != -1: return null
	if rooms_layer.get_cell_source_id(cell) != -1: return null
	return create_job("assign_room", cell, {"room_kind": room_kind})

func create_unassign_room_job(cell: Vector2i) -> Job:
	if rooms_layer == null: return null
	if rooms_layer.get_cell_source_id(cell) == -1: return null
	return create_job("unassign_room", cell)

func ensure_farm_harvest_job(cell: Vector2i) -> void:
	if get_job_at(cell, "farm_harvest") == null:
		create_job("farm_harvest", cell)

# dig/build jobs unchanged
func create_dig_job(cell: Vector2i) -> Job:
	if walls_layer == null: return null
	if walls_layer.get_cell_source_id(cell) == -1: return null
	return create_job("dig_wall", cell)

func create_build_job(cell: Vector2i) -> Job:
	if walls_layer == null: return null
	if walls_layer.get_cell_source_id(cell) != -1: return null
	return create_job("build_wall", cell)

# JobManager.gd
func ensure_place_furniture_job(cell: Vector2i, kind: String) -> void:
	if furniture_layer == null:
		push_error("JobManager: furniture_layer not set")
		return
	if get_job_at(cell, "place_furniture") != null:
		return
	# no walls
	if walls_layer != null and walls_layer.get_cell_source_id(cell) != -1:
		return
	# no overlapping furniture
	if furniture_layer.get_cell_source_id(cell) != -1:
		return

	# Helper: must have at least one adjacent walkable tile so a goblin can stand/operate
	var has_adjacent_walkable := false
	for d in DIR4:
		if GridNav.is_walkable(cell + d):
			has_adjacent_walkable = true
			break

	if kind == "well":
		# MUST be on a water tile
		if typeof(WaterTiles) == TYPE_NIL or not WaterTiles.is_water(cell):
			push_warning("Well must be placed on water.")
			return
		if not has_adjacent_walkable:
			push_warning("No adjacent walkable tile next to the well location.")
			return
		create_job("place_furniture", cell, {"furniture_kind": "well"})
		return

	if kind == "bucket":
		# Buckets should NOT sit on water (optional, but sensible)
		if typeof(WaterTiles) != TYPE_NIL and WaterTiles.is_water(cell):
			push_warning("Bucket cannot be placed on water.")
			return
		if not has_adjacent_walkable:
			# you might allow buckets in tight corners; keep or remove this guard as you like
			push_warning("No adjacent walkable tile next to the bucket location.")
			return
		create_job("place_furniture", cell, {"furniture_kind": "bucket"})
		return

	# default path for other furniture kinds
	if not has_adjacent_walkable:
		push_warning("No adjacent walkable tile to operate this furniture.")
		return
	create_job("place_furniture", cell, {"furniture_kind": kind})

# cancel/reopen (with proper releases)
func reopen_job(job: Job) -> void:
	if job == null:
		return
		
	# Release bucket-withdraw if this was a bucket-source water haul
	if job.type == "haul_water" and String(job.data.get("source","")) == "bucket":
		if bool(job.data.get("withdraw_reserved", false)):
			WaterSystem.release_bucket_withdraw(job.target_cell)
			job.data.erase("withdraw_reserved")

	# If this was a water-from-ground haul and we reserved a pile unit, release it.
	if job.type.begins_with("haul_"):
		if String(job.data.get("kind","")) == "water" and String(job.data.get("source","")) == "ground":
			if bool(job.data.get("pile_reserved", false)):
				WaterSystem.release_pile(job.target_cell)
				job.data.erase("pile_reserved")

	# Special-case: water hauls should be CANCELLED (not reopened)
	if job.type == "haul_water" and job.data.has("deposit_target") and String(job.data["deposit_target"]) == "bucket":
		if job.data.has("deposit_cell"):
			var bcell: Vector2i = job.data["deposit_cell"]
			WaterSystem.release_bucket(bcell)
			WaterSystem.clear_pending_for_bucket(bcell)
		job.status = Job.Status.CANCELLED
		job_updated.emit(job)
		return

	# Normal hauls (rock/carrot)
	if job.type.begins_with("haul_") and job.data.has("deposit_cell"):
		var kind := String(job.data.get("kind", "rock"))
		Inventory.release_cell(job.data["deposit_cell"] as Vector2i, kind)
		job.data.erase("deposit_cell")

	job.status = Job.Status.OPEN
	job.reserved_by = NodePath("")
	job_updated.emit(job)

func cancel_job(job: Job) -> void:
	if job == null:
		return
		
	# Release bucket-withdraw if this was a bucket-source water haul
	if job.type == "haul_water" and String(job.data.get("source","")) == "bucket":
		if bool(job.data.get("withdraw_reserved", false)):
			WaterSystem.release_bucket_withdraw(job.target_cell)
			job.data.erase("withdraw_reserved")

	# If this was a farm delivery, clear its pending and re-request so it can pick a new source
	if job.type == "haul_water" and job.data.has("deposit_target") and String(job.data["deposit_target"]) == "farm":
		if job.data.has("deposit_cell"):
			var fcell: Vector2i = job.data["deposit_cell"]
			WaterSystem.clear_pending_for_farm(fcell)
			WaterSystem.request_one_shot_water_to_farm(fcell)

	# Release bucket-withdraw if this was a bucket-source water haul
	if job.type == "haul_water" and String(job.data.get("source","")) == "bucket":
		if bool(job.data.get("withdraw_reserved", false)):
			WaterSystem.release_bucket_withdraw(job.target_cell)
			job.data.erase("withdraw_reserved")

	# If this was a water-from-ground haul and we reserved a pile unit, release it.
	if job.type.begins_with("haul_"):
		if String(job.data.get("kind","")) == "water" and String(job.data.get("source","")) == "ground":
			if bool(job.data.get("pile_reserved", false)):
				WaterSystem.release_pile(job.target_cell)
				job.data.erase("pile_reserved")
				
	if job.type == "haul_water" and job.data.has("deposit_target") and String(job.data["deposit_target"]) == "bucket":
		if job.data.has("deposit_cell"):
			var bcell2: Vector2i = job.data["deposit_cell"]
			WaterSystem.release_bucket(bcell2)
			WaterSystem.clear_pending_for_bucket(bcell2)
		job.data.erase("deposit_cell")

	elif job.type.begins_with("haul_") and job.data.has("deposit_cell"):
		var kind2 := String(job.data.get("kind", "rock"))
		Inventory.release_cell(job.data["deposit_cell"] as Vector2i, kind2)
		job.data.erase("deposit_cell")

	# If a well job is cancelled, unstick any buckets that were "await_well" on this well
	if job.type == "well_operate":
		WaterSystem.clear_awaiting_for_well(job.target_cell)

	job.status = Job.Status.CANCELLED
	job_updated.emit(job)


# ===== Internal helpers =======================================================
# --- helper near the top or under "Job utils" ---------------------------------  # NEW
func _is_allowed_in_cell_for(cell: Vector2i, kind: String) -> bool:
	var rules := Inventory.get_rules_for_cell(cell)
	var any_allowed := bool(rules.get("any", true))
	if any_allowed: return true
	var allowed_any: Array = rules.get("allowed", [])
	for k in allowed_any:
		if String(k) == kind:
			return true
	return false

func _pick_allowed_deposit_cell(kind: String, near_cell: Vector2i) -> Variant:
	# Water is never routed to inventory.
	if kind == "water":
		return null

	var dc = Inventory.find_best_deposit_cell_for_item(near_cell, kind)
	if dc == null:
		return null
	var cell: Vector2i = dc

	if _is_allowed_in_cell_for(cell, kind) and Inventory.cell_free_effective_for(cell, kind) > 0:
		return cell

	var area: Array[Vector2i] = Inventory.area_cells_for(cell)
	for c in area:
		if _is_allowed_in_cell_for(c, kind) and Inventory.cell_free_effective_for(c, kind) > 0:
			return c

	return null


func _ensure_build_tile_defaults() -> void:
	if walls_layer == null: return
	if build_wall_source_id != -1: return
	var used: PackedVector2Array = walls_layer.get_used_cells()
	if used.size() > 0:
		var sample: Vector2i = used[0]
		build_wall_source_id = walls_layer.get_cell_source_id(sample)
		build_wall_atlas_coords = walls_layer.get_cell_atlas_coords(sample)
		var alt := 0
		if walls_layer.has_method("get_cell_alternative_tile"):
			alt = walls_layer.get_cell_alternative_tile(sample)
		build_wall_alternative_tile = alt
	else:
		push_warning("JobManager: set wall tiles in the Inspector.")

func _ensure_room_tile_defaults(room_kind: String) -> void:
	if rooms_layer == null:
		return

	if room_kind == "treasury":
		if room_treasury_source_id != -1:
			return

		# 1) Prefer sampling an existing treasury cell (registered by Inventory)
		if Inventory != null and Inventory.treasury_cells.size() > 0:
			for c in Inventory.treasury_cells.keys():
				var sample: Vector2i = c
				room_treasury_source_id = rooms_layer.get_cell_source_id(sample)
				room_treasury_atlas_coords = rooms_layer.get_cell_atlas_coords(sample)
				var alt := 0
				if rooms_layer.has_method("get_cell_alternative_tile"):
					alt = rooms_layer.get_cell_alternative_tile(sample)
				room_treasury_alt = alt
				return

		# 2) Otherwise, scan Rooms and pick a tile that is NOT the farm signature (if known)
		var used: PackedVector2Array = rooms_layer.get_used_cells()
		if used.size() > 0:
			var picked: Variant = null
			# try to avoid farm tiles if we know their signature
			var have_farm_sig := (room_farm_source_id != -1)
			for u in used:
				var sid := rooms_layer.get_cell_source_id(u)
				var at  := rooms_layer.get_cell_atlas_coords(u)
				var alt2 := 0
				if rooms_layer.has_method("get_cell_alternative_tile"):
					alt2 = rooms_layer.get_cell_alternative_tile(u)
				if have_farm_sig:
					if not (sid == room_farm_source_id and at == room_farm_atlas_coords and alt2 == room_farm_alt):
						picked = u
						break
				else:
					picked = u
					break

			if picked != null:
				var p: Vector2i = picked
				room_treasury_source_id = rooms_layer.get_cell_source_id(p)
				room_treasury_atlas_coords = rooms_layer.get_cell_atlas_coords(p)
				var alt3 := 0
				if rooms_layer.has_method("get_cell_alternative_tile"):
					alt3 = rooms_layer.get_cell_alternative_tile(p)
				room_treasury_alt = alt3
			else:
				push_warning("JobManager: could not auto-detect a treasury tile (rooms layer has only farm tiles).")

		else:
			push_warning("JobManager: rooms_layer has no used cells; set treasury tile in the Inspector.")

	elif room_kind == "farm":
		# Keep your existing behavior for farm defaults
		if room_farm_source_id != -1:
			return
		var used2: PackedVector2Array = rooms_layer.get_used_cells()
		if used2.size() > 0:
			var sample2: Vector2i = used2[0]
			room_farm_source_id = rooms_layer.get_cell_source_id(sample2)
			room_farm_atlas_coords = rooms_layer.get_cell_atlas_coords(sample2)
			var altf := 0
			if rooms_layer.has_method("get_cell_alternative_tile"):
				altf = rooms_layer.get_cell_alternative_tile(sample2)
			room_farm_alt = altf
		else:
			push_warning("JobManager: set farm tiles in the Inspector.")


func _is_cell_occupied_by_worker(cell: Vector2i) -> bool:
	if floor_layer == null: return false
	for n in get_tree().get_nodes_in_group("workers"):
		if n is Node2D:
			var wcell := GridNav.world_to_cell(n.global_position, floor_layer)
			if wcell == cell: return true
	return false

func _find_reachable_adjacent(worker: Node2D, target_cell: Vector2i) -> Variant:
	if floor_layer == null: return null
	var start_cell := GridNav.world_to_cell(worker.global_position, floor_layer)
	for d in DIR4:
		var n = target_cell + d
		if not GridNav.is_walkable(n): continue
		var path = GridNav.find_path_cells(start_cell, n)
		if not path.is_empty(): return n
	return null

# Items-layer visuals (unchanged logic, but reads Inventory/GroundItems)
func _refresh_item_cell_visual(cell: Vector2i) -> void:
	if items_layer == null:
		return

	var show_kind := ""
	var total := 0

	# Treat as storage if either (a) Inventory marks it as treasury OR
	# (b) Inventory actually has stored items for that cell (safety for race/order).
	var is_storage := false
	if Inventory != null:
		is_storage = Inventory.is_treasury_cell(cell) or Inventory.contents.has(cell)

	if is_storage:
		# Try to show the assigned stack first
		var assigned := ""
		if Inventory != null and Inventory.has_method("get_assigned_kind"):
			assigned = Inventory.get_assigned_kind(cell)
		if assigned != "":
			var stored := 0
			if Inventory != null and Inventory.has_method("get_stored"):
				stored = Inventory.get_stored(cell, assigned)
			var ground_same := GroundItems.count(cell, assigned)
			total = stored + ground_same
			show_kind = assigned
		else:
			# No assigned kind; pick the first non-zero stored kind
			var bucket: Dictionary = {} if Inventory == null else Inventory.contents.get(cell, {})
			for k in bucket.keys():
				var cnt := int(bucket[k])
				if cnt > 0:
					show_kind = String(k)
					total = cnt
					break
			# If nothing stored, fall back to the largest ground stack for a hint
			if show_kind == "":
				var gb: Dictionary = GroundItems.items_on_ground.get(cell, {})
				var best := 0
				for gk in gb.keys():
					var c := int(gb[gk])
					if c > best:
						best = c
						show_kind = String(gk)
				total = best
	else:
		# Non-treasury cell: just show the largest ground pile, if any
		var gb2: Dictionary = GroundItems.items_on_ground.get(cell, {})
		var best2 := 0
		for gk2 in gb2.keys():
			var c2 := int(gb2[gk2])
			if c2 > best2:
				best2 = c2
				show_kind = String(gk2)
		total = best2

	# Clear sprite if nothing to show
	if total <= 0 or show_kind == "":
		items_layer.erase_cell(cell)
		return

	# Choose the tile by kind
	if show_kind == "rock":
		if rock_source_id == -1: return
		var idx := _index_for_count(total, rock_stack_max_per_cell)
		var atlas = [rock_atlas_coords_0, rock_atlas_coords_1, rock_atlas_coords_2, rock_atlas_coords_3][idx]
		items_layer.set_cell(cell, rock_source_id, atlas, rock_alt)
	elif show_kind == "carrot":
		if carrot_source_id == -1: return
		var idx2 := _index_for_count(total, carrot_stack_max_per_cell)
		var atlas2 = [carrot_atlas_coords_0, carrot_atlas_coords_1, carrot_atlas_coords_2, carrot_atlas_coords_3][idx2]
		items_layer.set_cell(cell, carrot_source_id, atlas2, carrot_alt)
	else:
		# unknown kind? just clear for now (you can extend here later)
		items_layer.erase_cell(cell)

func _index_for_count(count: int, max_per_cell: int) -> int:
	var maxv = max(1, max_per_cell)
	var r := float(count) / float(maxv)
	if r <= 0.25: return 0
	elif r <= 0.5: return 1
	elif r <= 0.75: return 2
	else: return 3

# --- Compatibility wrapper API (keeps old ClickInput working) -----------------

func ensure_dig_job(cell: Vector2i) -> void:
	if walls_layer == null:
		return
	var src_id: int = walls_layer.get_cell_source_id(cell)
	if src_id == -1:
		return                      # no wall to dig
	if has_job_at(cell, "dig_wall"):
		return
	create_dig_job(cell)

func ensure_build_job(cell: Vector2i) -> void:
	if walls_layer == null:
		return
	var src_id: int = walls_layer.get_cell_source_id(cell)
	if src_id != -1:
		return                      # already a wall here
	if has_job_at(cell, "build_wall"):
		return
	create_build_job(cell)

func ensure_assign_room_job(cell: Vector2i, room_kind: String) -> void:
	if rooms_layer == null:
		return
	# only assign on non-wall cells
	if walls_layer != null and walls_layer.get_cell_source_id(cell) != -1:
		return
	# skip if already assigned or already has an assign job
	if rooms_layer.get_cell_source_id(cell) != -1:
		return
	if has_job_at(cell, "assign_room"):
		return
	create_assign_room_job(cell, room_kind)

func ensure_unassign_room_job(cell: Vector2i) -> void:
	if rooms_layer == null:
		return
	# only unassign if there is a room there and no unassign job yet
	if rooms_layer.get_cell_source_id(cell) == -1:
		return
	if has_job_at(cell, "unassign_room"):
		return
	create_unassign_room_job(cell)

func remove_room_job_at(cell: Vector2i) -> void:
	var j: Job = get_job_at(cell, "assign_room")
	if j == null:
		j = get_job_at(cell, "unassign_room")
	if j != null and (j.status == Job.Status.OPEN or j.status == Job.Status.RESERVED):
		cancel_job(j)

func remove_job_at(cell: Vector2i, type: String) -> void:
	var j: Job = get_job_at(cell, type)
	if j == null:
		return
	if j.status == Job.Status.OPEN or j.status == Job.Status.RESERVED:
		cancel_job(j)
