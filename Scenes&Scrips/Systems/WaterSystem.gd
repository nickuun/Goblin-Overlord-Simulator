# res://Scripts/WaterSystem.gd
extends Node

var furniture_layer: TileMapLayer

var well_cells: Dictionary = {}           # cell -> true
var bucket_cells: Dictionary = {}         # cell -> true

@export var bucket_capacity_per_bucket: int = 4
var bucket_water: Dictionary = {}         # bucket cell -> stored water
var bucket_reserved: Dictionary = {}      # bucket cell -> reserved slots (deliveries in-flight)
var bucket_withdraw_reserved: Dictionary = {} # bucket cell -> reserved pickups (farm pulls)

# Per-bucket pending state:
#   { "state": "await_well" | "await_delivery", "well": Vector2i }
var pending_by_bucket: Dictionary = {}    # bucket cell -> dict

# Per-farm pending:
#   true  => one-shot haul is in-flight
#   {"state":"await_well","well":Vector2i} => waiting for a specific well to produce
var pending_farms: Dictionary = {}        # farm_cell -> true or dict
var pile_reserved: Dictionary = {}  # well_cell -> reserved count

const DIR4 := [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]

func _steps(from_cell: Vector2i, to_cell: Vector2i) -> int:
	var p = GridNav.find_path_cells(from_cell, to_cell)
	if p.is_empty():
		return -1
	return max(0, p.size() - 1)

func _steps_to_adjacent(from_cell: Vector2i, center: Vector2i) -> int:
	var best := -1
	for d in DIR4:
		var n = center + d
		if not GridNav.is_walkable(n):
			continue
		var s := _steps(from_cell, n)
		if s == -1:
			continue
		if best == -1 or s < best:
			best = s
	return best


func init(furniture: TileMapLayer) -> void:
	pile_reserved.clear()
	furniture_layer = furniture
	well_cells.clear()
	bucket_cells.clear()
	bucket_water.clear()
	bucket_reserved.clear()
	bucket_withdraw_reserved.clear()
	pending_by_bucket.clear()
	pending_farms.clear()

func on_place_furniture(cell: Vector2i, kind: String) -> void:
	if kind == "well":
		well_cells[cell] = true
	elif kind == "bucket":
		bucket_cells[cell] = true
		bucket_water[cell] = 0
		bucket_reserved[cell] = 0
		bucket_withdraw_reserved[cell] = 0
		clear_pending_for_bucket(cell)

# ------------------------------------------------------------------------
# Bucket helpers
# ------------------------------------------------------------------------
# --- Well ground-water reservation helpers (per-well pile) ---
func _pile_available(cell: Vector2i) -> int:
	# Use the autoloaded GroundItems store
	var ground := GroundItems.count(cell, "water")
	var reserved := int(pile_reserved.get(cell, 0))
	return max(0, ground - reserved)

func reserve_pile(cell: Vector2i) -> bool:
	if _pile_available(cell) > 0:
		pile_reserved[cell] = int(pile_reserved.get(cell, 0)) + 1
		return true
	return false

func release_pile(cell: Vector2i) -> void:
	pile_reserved[cell] = max(0, int(pile_reserved.get(cell, 0)) - 1)

# Called by WorkerAgent when arriving at the well to pick up the unit reserved for this job.
# This only converts the reservation to "consumed"; WorkerAgent still calls JobManager.take_item(...)
func consume_pile(cell: Vector2i) -> bool:
	var r := int(pile_reserved.get(cell, 0))
	if r <= 0:
		return false
	pile_reserved[cell] = r - 1
	return true


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

# withdraws (bucket -> farm)
func has_bucket_water(cell: Vector2i) -> bool:
	return int(bucket_water.get(cell, 0)) - int(bucket_withdraw_reserved.get(cell, 0)) > 0

func reserve_bucket_withdraw(cell: Vector2i) -> bool:
	# reserve if any available
	if has_bucket_water(cell):
		bucket_withdraw_reserved[cell] = int(bucket_withdraw_reserved.get(cell, 0)) + 1
		return true
	return false

func release_bucket_withdraw(cell: Vector2i) -> void:
	bucket_withdraw_reserved[cell] = max(0, int(bucket_withdraw_reserved.get(cell, 0)) - 1)

# called by WorkerAgent when it arrives at the bucket to "pick up"
func consume_bucket_withdraw(cell: Vector2i) -> bool:
	var r := int(bucket_withdraw_reserved.get(cell, 0))
	var cur := int(bucket_water.get(cell, 0))
	if r <= 0 or cur <= 0:
		return false
	bucket_withdraw_reserved[cell] = r - 1
	bucket_water[cell] = cur - 1
	return true

# ------------------------------------------------------------------------
# Farm one-shot water request
#   - chooses the nearest source:
#       * nearest WELL **with ground water**, or
#       * nearest BUCKET with water
#     If neither exists:
#       * compare nearest BUCKET with water vs nearest WELL (empty):
#           - if nearest empty WELL is closer than any bucket, operate it and wait
#           - else, haul from the bucket
# ------------------------------------------------------------------------
func request_one_shot_water_to_farm(farm_cell: Vector2i) -> void:
	if pending_farms.has(farm_cell):
		return
	if FarmSystem.has_plot(farm_cell):
		var p := FarmSystem.get_plot(farm_cell)
		if bool(p.get("watered", false)):
			return

	# ----- nearest bucket with water -----
	var have_bucket := false
	var bucket_cell := Vector2i.ZERO
	var bucket_steps := 0
	for bc in bucket_cells.keys():
		if has_bucket_water(bc):
			var sb := _steps(farm_cell, bc)
			if sb == -1:
				continue
			if (not have_bucket) or sb < bucket_steps:
				have_bucket = true
				bucket_steps = sb
				bucket_cell = bc

	# ----- nearest well with a ground water pile -----
	var have_pile := false
	var pile_well := Vector2i.ZERO
	var pile_steps := 0
	for wc in well_cells.keys():
		if JobManager.has_ground_item(wc, "water"):
			var sw := _steps(farm_cell, wc)
			if sw == -1:
				continue
			if (not have_pile) or sw < pile_steps:
				have_pile = true
				pile_steps = sw
				pile_well = wc

	# ----- nearest reachable well (even if empty) -> measure to ADJACENT -----
	var have_empty := false
	var empty_well := Vector2i.ZERO
	var empty_steps := 0
	for w0 in well_cells.keys():
		var s0 := _steps_to_adjacent(farm_cell, w0)
		if s0 == -1:
			continue
		if (not have_empty) or s0 < empty_steps:
			have_empty = true
			empty_steps = s0
			empty_well = w0

	# ----- pick the true minimum across pile / bucket / empty-well -----
	var choice_kind := ""           # "pile" | "bucket" | "empty"
	var choice_cell := Vector2i.ZERO
	var choice_steps := 0

	if have_pile:
		choice_kind = "pile"
		choice_cell = pile_well
		choice_steps = pile_steps

	if have_bucket and (choice_kind == "" or bucket_steps < choice_steps):
		choice_kind = "bucket"
		choice_cell = bucket_cell
		choice_steps = bucket_steps

	if have_empty and (choice_kind == "" or empty_steps < choice_steps):
		choice_kind = "empty"
		choice_cell = empty_well
		choice_steps = empty_steps

	if choice_kind == "":
		return  # nothing reachable

	# ----- enact choice -----
	if choice_kind == "pile":
		# Reserve one unit from the well pile; only then create the job
		if reserve_pile(choice_cell):
			# avoid duplicates to this farm
			if not _has_specific_haul_to_farm(choice_cell, farm_cell):
				JobManager.create_job("haul_water", choice_cell, {
					"kind": "water",
					"count": 1,
					"deposit_target": "farm",
					"deposit_cell": farm_cell,
					"source": "ground"
				})
			pending_farms[farm_cell] = true
		else:
			# No unreserved unit: treat like empty well -> spin it and wait
			if JobManager.get_job_at(choice_cell, "well_operate") == null:
				JobManager.create_job("well_operate", choice_cell)
			pending_farms[farm_cell] = {"state":"await_well", "well": choice_cell}
		return


	if choice_kind == "bucket":
		# Reserve one withdrawal so two farms don't fight over the same unit.
		# Only create the job if reservation succeeded (race-safe).
		if reserve_bucket_withdraw(choice_cell):
			JobManager.create_job("haul_water", choice_cell, {
				"kind": "water",
				"count": 1,
				"deposit_target": "farm",
				"deposit_cell": farm_cell,
				"source": "bucket"
			})
			pending_farms[farm_cell] = true
			return
		# fallback if reservation lost the race:
		if have_pile and (not have_empty or pile_steps <= empty_steps):
			if reserve_pile(pile_well):
				if not _has_specific_haul_to_farm(pile_well, farm_cell):
					JobManager.create_job("haul_water", pile_well, {
						"kind":"water", "count":1,
						"deposit_target":"farm",
						"deposit_cell": farm_cell,
						"source":"ground"
					})
				pending_farms[farm_cell] = true
				return
			# no unreserved unit; spin an empty well if available
			if have_empty:
				if JobManager.get_job_at(empty_well, "well_operate") == null:
					JobManager.create_job("well_operate", empty_well)
				pending_farms[farm_cell] = {"state":"await_well", "well": empty_well}
				return
			return


	# choice_kind == "empty" → operate well, then we’ll haul when on_well_operate_completed fires
	if JobManager.get_job_at(choice_cell, "well_operate") == null:
		JobManager.create_job("well_operate", choice_cell)
	pending_farms[farm_cell] = {"state": "await_well", "well": choice_cell}

func clear_pending_for_farm(cell: Vector2i) -> void:
	pending_farms.erase(cell)

# Optional helper if you ever cancel a well job by hand and want farms to give up waiting on it
func clear_awaiting_for_well(well_cell: Vector2i) -> void:
	var drop: Array[Vector2i] = []
	for fc in pending_farms.keys():
		var st = pending_farms[fc]
		if st is Dictionary and String(st.get("state","")) == "await_well" and Vector2i(st.get("well", Vector2i.ZERO)) == well_cell:
			drop.append(fc)
	for d in drop:
		pending_farms.erase(d)

# ------------------------------------------------------------------------
# Scheduler entry (called by JobManager.request_job() each time)
#   Self-heals stuck buckets and creates new jobs as needed.
# ------------------------------------------------------------------------
func ensure_supply_jobs() -> void:
	_validate_pending_buckets()

	for bc in bucket_cells.keys():
		var bcell: Vector2i = bc

		# full? -> drop any stale pending and skip
		if bucket_free_effective(bcell) <= 0:
			clear_pending_for_bucket(bcell)
			continue

		# one in-flight step per bucket
		if pending_by_bucket.has(bcell):
			continue

		# 1) Prefer hauling existing ground water (closest well)
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
			# Reserve from the well pile; only then create a specific haul to THIS bucket
			if reserve_pile(best_well):
				JobManager.create_job("haul_water", best_well, {
					"kind": "water",
					"count": 1,
					"deposit_cell": bcell,
					"deposit_target": "bucket",
					"source": "ground"
				})
				pending_by_bucket[bcell] = {"state":"await_delivery", "well": best_well}
			else:
				# No unreserved unit left: spin the well again instead
				if JobManager.get_job_at(best_well, "well_operate") == null:
					JobManager.create_job("well_operate", best_well)
				pending_by_bucket[bcell] = {"state":"await_well", "well": best_well}
			continue


		# 2) Otherwise operate the closest reachable idle well
		var picked := false
		var chosen := Vector2i.ZERO
		var best_steps2 := 0
		for wc2 in well_cells.keys():
			if JobManager.get_job_at(wc2, "well_operate") != null:
				continue # someone else already spinning this well right now
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
		# If nothing reachable, we do nothing this tick; try again next call.

# Self-heal: if a bucket is "await_delivery" but the water pile vanished (another job took it),
# re-issue the well op; if a bucket is "await_well" but no job exists, re-issue the op.
func _validate_pending_buckets() -> void:
	var to_clear: Array[Vector2i] = []

	for b in pending_by_bucket.keys():
		# full bucket? clear and move on
		if bucket_free_effective(b) <= 0:
			to_clear.append(b)
			continue

		var entry: Dictionary = pending_by_bucket[b]
		var state := String(entry.get("state",""))
		var wcell: Vector2i = Vector2i(entry.get("well", Vector2i.ZERO))

		if JobManager.has_ground_item(wcell, "water"):
			if reserve_pile(wcell):
				# avoid duplicates: only create if not already hauling from this well to THIS bucket
				if not _has_specific_haul_to_bucket(wcell, b):
					JobManager.create_job("haul_water", wcell, {
						"kind":"water", "count":1,
						"deposit_cell": b, "deposit_target":"bucket",
						"source":"ground"
					})
				pending_by_bucket[b] = {"state":"await_delivery", "well": wcell}
			else:
				# No free unit; ensure well is spinning
				if JobManager.get_job_at(wcell, "well_operate") == null:
					JobManager.create_job("well_operate", wcell)
				pending_by_bucket[b] = {"state":"await_well", "well": wcell}

		if JobManager.has_ground_item(wcell, "water"):
			if reserve_pile(wcell):
				if not _has_specific_haul_to_bucket(wcell, b):
					JobManager.create_job("haul_water", wcell, {
						"kind":"water", "count":1,
						"deposit_cell": b, "deposit_target":"bucket",
						"source":"ground"
					})
				pending_by_bucket[b] = {"state":"await_delivery", "well": wcell}
			else:
				# ensure a spin job exists
				if JobManager.get_job_at(wcell, "well_operate") == null:
					JobManager.create_job("well_operate", wcell)



	for c in to_clear:
		clear_pending_for_bucket(c)

# helper: is there a haul_water job from this well to THIS bucket?
func _has_specific_haul_to_bucket(well_cell: Vector2i, bucket_cell: Vector2i) -> bool:
	for j in JobManager.jobs:
		if j.type == "haul_water" and j.target_cell == well_cell and (j.status == Job.Status.OPEN or j.status == Job.Status.RESERVED or j.status == Job.Status.ACTIVE):
			var dt := String(j.data.get("deposit_target",""))
			if dt == "bucket" and Vector2i(j.data.get("deposit_cell", Vector2i.ZERO)) == bucket_cell:
				return true
	return false

func _has_specific_haul_to_farm(well_cell: Vector2i, farm_cell: Vector2i) -> bool:
	for j in JobManager.jobs:
		if j.type == "haul_water" and j.target_cell == well_cell and (j.status == Job.Status.OPEN or j.status == Job.Status.RESERVED or j.status == Job.Status.ACTIVE):
			var dt := String(j.data.get("deposit_target",""))
			if dt == "farm" and Vector2i(j.data.get("deposit_cell", Vector2i.ZERO)) == farm_cell:
				return true
	return false
# ------------------------------------------------------------------------
# When a well operation completes (JobManager calls this)
#   - drop 1 water on the well
#   - feed a waiting farm bound to THIS well first (if any), else nearest "free" farm
#   - then feed ONE bucket that was awaiting THIS well
# ------------------------------------------------------------------------
func on_well_operate_completed(well_cell: Vector2i) -> void:
	# produce one water on the well tile
	JobManager.drop_item(well_cell, "water", 1)

	# 1) Serve a farm waiting on THIS well (state==await_well, well==well_cell)
	var target_farm: Variant = null
	for fc in pending_farms.keys():
		var st = pending_farms[fc]
		if st is Dictionary and String(st.get("state","")) == "await_well" and Vector2i(st.get("well", Vector2i.ZERO)) == well_cell:
			target_farm = fc
			break

	# else, serve nearest farm with no in-flight (i.e., not 'true')
	if target_farm == null:
		var has := false
		var best_steps := 0
		for fc2 in pending_farms.keys():
			# skip already-in-flight
			if pending_farms[fc2] == true:
				continue
			# skip farms explicitly waiting for some well we didn't satisfy
			if pending_farms[fc2] is Dictionary:
				continue
			var steps := _steps(well_cell, fc2)
			if steps == -1:
				continue
			if not has or steps < best_steps:
				has = true
				best_steps = steps
				target_farm = fc2

	if target_farm != null:
		if reserve_pile(well_cell):
			if not _has_specific_haul_to_farm(well_cell, target_farm):
				JobManager.create_job("haul_water", well_cell, {
					"kind":"water","count":1,
					"deposit_target":"farm",
					"deposit_cell": target_farm,
					"source":"ground"
				})
			pending_farms[target_farm] = true
		return

	# 2) Serve ONE bucket that was waiting on THIS well
	var target_bucket := Vector2i.ZERO
	var found := false
	for b in pending_by_bucket.keys():
		var entry: Dictionary = pending_by_bucket[b]
		if String(entry.get("state","")) == "await_well" and Vector2i(entry.get("well", Vector2i.ZERO)) == well_cell:
			target_bucket = b
			found = true
			break

	if found and JobManager.has_ground_item(well_cell, "water"):
		if reserve_pile(well_cell):
			if not _has_specific_haul_to_bucket(well_cell, target_bucket):
				JobManager.create_job("haul_water", well_cell, {
					"kind":"water","count":1,
					"deposit_cell": target_bucket,
					"deposit_target":"bucket",
					"source":"ground"
				})
			pending_by_bucket[target_bucket] = {"state":"await_delivery", "well": well_cell}

func get_bucket_hover_text(cell: Vector2i) -> String:
	if not bucket_cells.has(cell):
		return ""
	var stored := bucket_stored(cell)
	var cap := bucket_capacity(cell)
	var incoming := bucket_reserved_count(cell)
	var outgoing := int(bucket_withdraw_reserved.get(cell, 0))
	return "[Bucket] %d/%d  (in:+%d  out:-%d)" % [stored, cap, incoming, outgoing]

func _count_spin_jobs(well_cell: Vector2i) -> int:
	var n := 0
	for j in JobManager.jobs:
		if j.target_cell == well_cell and j.type == "well_operate":
			if j.status == Job.Status.OPEN or j.status == Job.Status.RESERVED or j.status == Job.Status.ACTIVE:
				n += 1
	return n

func _count_haul_from_well(well_cell: Vector2i) -> int:
	var n := 0
	for j in JobManager.jobs:
		if j.target_cell == well_cell and j.type == "haul_water":
			if j.status == Job.Status.OPEN or j.status == Job.Status.RESERVED or j.status == Job.Status.ACTIVE:
				n += 1
	return n

func _count_buckets_awaiting(well_cell: Vector2i) -> int:
	var n := 0
	for b in pending_by_bucket.keys():
		var entry: Dictionary = pending_by_bucket[b]
		if String(entry.get("state","")) == "await_well" and Vector2i(entry.get("well", Vector2i.ZERO)) == well_cell:
			n += 1
	return n

func _count_farms_awaiting(well_cell: Vector2i) -> int:
	var n := 0
	for fc in pending_farms.keys():
		var st = pending_farms[fc]
		if st is Dictionary and String(st.get("state","")) == "await_well" and Vector2i(st.get("well", Vector2i.ZERO)) == well_cell:
			n += 1
	return n

func get_well_hover_text(cell: Vector2i) -> String:
	if not well_cells.has(cell):
		return ""
	var pile := GroundItems.count(cell, "water")
	var spins := _count_spin_jobs(cell)
	var hauls := _count_haul_from_well(cell)
	var wait_b := _count_buckets_awaiting(cell)
	var wait_f := _count_farms_awaiting(cell)
	return "[Well] pile:%d  spin_jobs:%d  hauls_out:%d  waiting(b:%d f:%d)" % [pile, spins, hauls, wait_b, wait_f]
