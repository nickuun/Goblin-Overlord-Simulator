# res://Scripts/WaterSystem.gd
extends Node

var furniture_layer: TileMapLayer

var well_cells: Dictionary = {}          # cell -> true
var bucket_cells: Dictionary = {}        # cell -> true

@export var bucket_capacity_per_bucket: int = 4
var bucket_water: Dictionary = {}        # bucket cell -> stored water
var bucket_reserved: Dictionary = {}     # bucket cell -> reserved slots (in-flight hauls)

# One in-flight step per bucket:
# { "state": "await_well" | "await_delivery", "well": Vector2i }
var pending_by_bucket: Dictionary = {}   # bucket cell -> dict

func init(furniture: TileMapLayer) -> void:
	furniture_layer = furniture
	well_cells.clear()
	bucket_cells.clear()
	bucket_water.clear()
	bucket_reserved.clear()
	pending_by_bucket.clear()

func on_place_furniture(cell: Vector2i, kind: String) -> void:
	if kind == "well":
		well_cells[cell] = true
	elif kind == "bucket":
		bucket_cells[cell] = true
		bucket_water[cell] = 0
		bucket_reserved[cell] = 0
		pending_by_bucket.erase(cell)

# ----------------- bucket helpers -----------------
func clear_awaiting_for_well(well_cell: Vector2i) -> void:
	var to_clear: Array[Vector2i] = []
	for b in pending_by_bucket.keys():
		var e: Dictionary = pending_by_bucket[b]
		if String(e.get("state", "")) == "await_well" and Vector2i(e.get("well", Vector2i.ZERO)) == well_cell:
			to_clear.append(b)
	for bc in to_clear:
		pending_by_bucket.erase(bc)

func bucket_capacity(cell: Vector2i) -> int:
	return bucket_capacity_per_bucket

func bucket_stored(cell: Vector2i) -> int:
	return int(bucket_water.get(cell, 0))

func bucket_reserved_count(cell: Vector2i) -> int:
	return int(bucket_reserved.get(cell, 0))

func bucket_free_effective(cell: Vector2i) -> int:
	return bucket_capacity(cell) - bucket_stored(cell) - bucket_reserved_count(cell)

func reserve_bucket(cell: Vector2i) -> void:
	bucket_reserved[cell] = bucket_reserved_count(cell) + 1

func release_bucket(cell: Vector2i) -> void:
	bucket_reserved[cell] = max(0, bucket_reserved_count(cell) - 1)

func add_bucket_water(cell: Vector2i, count: int) -> void:
	bucket_water[cell] = bucket_stored(cell) + count

func clear_pending_for_bucket(cell: Vector2i) -> void:
	pending_by_bucket.erase(cell)

# ----------------- scheduling -----------------
func ensure_supply_jobs() -> void:
	# For each bucket that has free space and no in-flight request,
	# either haul existing water or ask a well to produce one unit.
	for bc in bucket_cells.keys():
		var bcell: Vector2i = bc

		# if full, drop any stale pending
		if bucket_free_effective(bcell) <= 0:
			clear_pending_for_bucket(bcell)
			continue

		# already have a step in-flight for this bucket
		if pending_by_bucket.has(bcell):
			continue

		# 1) Prefer hauling existing water
		var best_well := Vector2i.ZERO
		var found := false
		var best_steps := 0
		for wc in well_cells.keys():
			if JobManager.has_ground_item(wc, "water"):
				var path = GridNav.find_path_cells(bcell, wc)
				if path.is_empty():
					continue
				var steps = max(0, path.size() - 1)
				if not found or steps < best_steps:
					found = true
					best_steps = steps
					best_well = wc
		if found:
			# exactly one haul to THIS bucket
			JobManager.create_job(
				"haul_water",
				best_well,
				{
					"kind": "water",
					"count": 1,
					"deposit_cell": bcell,
					"deposit_target": "bucket"
				}
			)
			pending_by_bucket[bcell] = {"state":"await_delivery", "well": best_well}
			continue

		# 2) Otherwise, ask ONE reachable idle well to produce
		var picked := false
		var chosen := Vector2i.ZERO
		var best_steps2 := 0
		for wc2 in well_cells.keys():
			if JobManager.get_job_at(wc2, "well_operate") != null:
				continue
			var p2 = GridNav.find_path_cells(bcell, wc2)
			if p2.is_empty():
				continue
			var steps2 = max(0, p2.size() - 1)
			if (not picked) or steps2 < best_steps2:
				picked = true
				best_steps2 = steps2
				chosen = wc2
		if picked:
			JobManager.create_job("well_operate", chosen)
			pending_by_bucket[bcell] = {"state":"await_well", "well": chosen}
		# if no reachable idle well, do nothing this tick; we'll retry next call

# Called by JobManager.complete_job when a well finishes
func on_well_operate_completed(well_cell: Vector2i) -> void:
	# produce one water on the well
	JobManager.drop_item(well_cell, "water", 1)

	# find ONE bucket that was waiting for THIS well
	var target_bucket := Vector2i.ZERO
	var found := false
	for b in pending_by_bucket.keys():
		var entry: Dictionary = pending_by_bucket[b]
		if String(entry.get("state", "")) == "await_well" and Vector2i(entry.get("well", Vector2i.ZERO)) == well_cell:
			target_bucket = b
			found = true
			break
	if not found:
		return

	# queue exactly one haul to that bucket; hand off to "await_delivery"
	if JobManager.has_ground_item(well_cell, "water"):
		JobManager.create_job(
			"haul_water",
			well_cell,
			{
				"kind": "water",
				"count": 1,
				"deposit_cell": target_bucket,
				"deposit_target": "bucket"
			}
		)
		pending_by_bucket[target_bucket] = {"state":"await_delivery", "well": well_cell}
