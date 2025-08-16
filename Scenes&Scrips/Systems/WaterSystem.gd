extends Node

# furniture
var furniture_layer: TileMapLayer = null
var well_cells: Dictionary = {}           # cell -> true
var bucket_cells: Dictionary = {}         # cell -> true

# buckets
@export var bucket_capacity_per_bucket: int = 4
var bucket_water: Dictionary = {}         # cell -> int
var bucket_reserved: Dictionary = {}      # cell -> int

# in-flight haul guard: one per bucket
var _pending_haul_to_bucket: Dictionary = {}  # cell -> true

func init(layer: TileMapLayer) -> void:
	furniture_layer = layer

func on_place_furniture(cell: Vector2i, kind: String) -> void:
	if kind == "well":
		well_cells[cell] = true
	elif kind == "bucket":
		bucket_cells[cell] = true
		bucket_water[cell] = 0
		bucket_reserved[cell] = 0

func on_well_operate_completed(well_cell: Vector2i) -> void:
	# create 1 water at the well and request a haul to a needy bucket
	GroundItems.drop_item(well_cell, "water", 1)
	for bc in bucket_cells.keys():
		var bcell: Vector2i = bc
		if bucket_free_effective(bcell) > 0 and not has_pending_for_bucket(bcell):
			var data := {
				"kind": "water",
				"count": 1,
				"deposit_cell": bcell,
				"deposit_target": "bucket"
			}
			JobManager.create_job("haul_water", well_cell, data)
			mark_pending_for_bucket(bcell)
			break

# bucket helpers
func is_bucket(cell: Vector2i) -> bool:
	return bucket_cells.has(cell)

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

# pending guard
func has_pending_for_bucket(cell: Vector2i) -> bool:
	return _pending_haul_to_bucket.has(cell)

func mark_pending_for_bucket(cell: Vector2i) -> void:
	_pending_haul_to_bucket[cell] = true

func clear_pending_for_bucket(cell: Vector2i) -> void:
	_pending_haul_to_bucket.erase(cell)

# ensure loop (called each request tick)
func ensure_supply_jobs() -> void:
	for bc in bucket_cells.keys():
		var bcell: Vector2i = bc
		if bucket_free_effective(bcell) <= 0:
			continue
		if has_pending_for_bucket(bcell):
			continue

		# prefer wells that already have water on ground
		for wc in well_cells.keys():
			if GroundItems.has(wc, "water"):
				var data := {
					"kind": "water",
					"count": 1,
					"deposit_cell": bcell,
					"deposit_target": "bucket"
				}
				JobManager.create_job("haul_water", wc, data)
				mark_pending_for_bucket(bcell)
				break
		if has_pending_for_bucket(bcell):
			continue

		# otherwise, operate any well; hauling will follow after water is produced
		for wc2 in well_cells.keys():
			JobManager.create_job("well_operate", wc2)
			break
