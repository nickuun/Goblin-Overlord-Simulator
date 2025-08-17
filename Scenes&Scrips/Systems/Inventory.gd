extends Node

signal inventory_changed()
signal spill_items(cell: Vector2i, kind: String, count: int)

const DIR4 := [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]

var rooms_layer: TileMapLayer = null
var capacity_per_tile: int = 10

# core maps
var treasury_cells: Dictionary = {}                      # cell -> true
var contents: Dictionary = {}                            # cell -> {kind:int}
var reserved_per_cell_kind: Dictionary = {}              # cell -> {kind:int}
var stack_kind: Dictionary = {}                          # cell -> "" or "rock"/"carrot"/etc

# areas & rules
var cell_area_id: Dictionary = {}                        # cell -> area_id
var area_id_cells: Dictionary = {}                       # area_id -> Array[Vector2i]
var area_rules: Dictionary = {}                          # area_id -> {"any": bool, "allowed": PackedStringArray}
var _prev_cell_area_id: Dictionary = {}

signal cell_changed(cell: Vector2i)           # single storage cell changed
signal area_changed(cells: Array[Vector2i])   # a set of storage cells changed


func init(_rooms: TileMapLayer, _capacity: int) -> void:
	rooms_layer = _rooms
	capacity_per_tile = _capacity
	rebuild_from_rooms_layer()

func rebuild_from_rooms_layer() -> void:
	treasury_cells.clear()
	if rooms_layer == null:
		return

	# Pull room signatures if JobManager is available
	var tre_src: int = -1
	var tre_at: Vector2i = Vector2i.ZERO
	var tre_alt: int = 0

	var farm_src: int = -1
	var farm_at: Vector2i = Vector2i.ZERO
	var farm_alt: int = 0

	if has_node("/root/JobManager"):
		var jm = get_node("/root/JobManager")
		tre_src = jm.room_treasury_source_id
		tre_at  = jm.room_treasury_atlas_coords
		tre_alt = jm.room_treasury_alt

		farm_src = jm.room_farm_source_id
		farm_at  = jm.room_farm_atlas_coords
		farm_alt = jm.room_farm_alt

	var used: PackedVector2Array = rooms_layer.get_used_cells()
	for c in used:
		var sid := rooms_layer.get_cell_source_id(c)
		var at  := rooms_layer.get_cell_atlas_coords(c)
		var alt := 0
		if rooms_layer.has_method("get_cell_alternative_tile"):
			alt = rooms_layer.get_cell_alternative_tile(c)

		var is_farm_tile := false
		var is_treasury_tile := false

		# 1) farm signature
		if farm_src != -1 and sid == farm_src and at == farm_at and alt == farm_alt:
			is_farm_tile = true

		# 2) treasury signature
		if tre_src != -1 and sid == tre_src and at == tre_at and alt == tre_alt:
			is_treasury_tile = true

		# 3) farm plots already registered
		if not is_farm_tile and typeof(FarmSystem) != TYPE_NIL and FarmSystem.has_plot(c):
			is_farm_tile = true

		# 4) final decision
		var mark_as_treasury := false
		if is_farm_tile:
			mark_as_treasury = false
		elif is_treasury_tile:
			mark_as_treasury = true
		else:
			# unknown room tile → treat as treasury (fallback)
			mark_as_treasury = true

		if mark_as_treasury:
			treasury_cells[c] = true
			if not contents.has(c): contents[c] = {}
			if not reserved_per_cell_kind.has(c): reserved_per_cell_kind[c] = {}
			if not stack_kind.has(c): stack_kind[c] = ""

	_recompute_areas()


# --- public queries -----------------------------------------------------------
func is_treasury_cell(cell: Vector2i) -> bool:
	return treasury_cells.has(cell)

func get_assigned_kind(cell: Vector2i) -> String:
	return String(stack_kind.get(cell, ""))

func get_stored(cell: Vector2i, kind: String) -> int:
	if not contents.has(cell):
		return 0
	return int((contents[cell] as Dictionary).get(kind, 0))

func get_inventory_totals() -> Dictionary:
	var out := {}
	for cell in contents.keys():
		var bucket: Dictionary = contents[cell]
		for k in bucket.keys():
			out[k] = int(out.get(k, 0)) + int(bucket[k])
	return out

# --- reserve/store ------------------------------------------------------------
func cell_capacity(cell: Vector2i) -> int:
	return capacity_per_tile

func _cell_reserved_kind(cell: Vector2i, kind: String) -> int:
	var b: Dictionary = reserved_per_cell_kind.get(cell, {})
	return int(b.get(kind, 0))

func cell_free_effective_for(cell: Vector2i, kind: String) -> int:
	if not is_treasury_cell(cell):
		return 0

	# RULES GATE
	var r := get_rules_for_cell(cell)
	var any_ok := bool(r.get("any", true))
	if not any_ok:
		var allowed: Array = r.get("allowed", [])
		var ok := false
		for s in allowed:
			if String(s) == kind:
				ok = true
				break
		if not ok:
			return 0

	# STACK GATE
	var assigned := get_assigned_kind(cell)
	if assigned != "" and assigned != kind:
		return 0

	return cell_capacity(cell) - get_stored(cell, kind) - _cell_reserved_kind(cell, kind)


func reserve_cell(cell: Vector2i, kind: String) -> void:
	var b: Dictionary = reserved_per_cell_kind.get(cell, {})
	b[kind] = int(b.get(kind, 0)) + 1
	reserved_per_cell_kind[cell] = b

func release_cell(cell: Vector2i, kind: String) -> void:
	var b: Dictionary = reserved_per_cell_kind.get(cell, {})
	b[kind] = max(0, int(b.get(kind, 0)) - 1)
	reserved_per_cell_kind[cell] = b

func add_item(cell: Vector2i, kind: String, count: int) -> void:
	if not contents.has(cell):
		contents[cell] = {}
	var bucket: Dictionary = contents[cell]
	bucket[kind] = int(bucket.get(kind, 0)) + count
	contents[cell] = bucket
	inventory_changed.emit()
	cell_changed.emit(cell)
	

# --- rules / areas ------------------------------------------------------------
func get_rules_for_cell(cell: Vector2i) -> Dictionary:
	var aid := int(cell_area_id.get(cell, -1))
	if aid == -1:
		return {"any": true, "allowed": [] as Array[String]}
	var r: Dictionary = area_rules.get(aid, {"any": true, "allowed": PackedStringArray()})
	var psa: PackedStringArray = r.get("allowed", PackedStringArray())
	var arr: Array[String] = []
	for s in psa:
		arr.append(String(s))
	return {"any": bool(r.get("any", true)), "allowed": arr}

func set_rules_for_cell(cell: Vector2i, any_allowed: bool, allowed: Array[String]) -> void:
	var aid := int(cell_area_id.get(cell, -1))
	if aid == -1:
		return
	var psa := PackedStringArray()
	for s in allowed:
		psa.append(String(s))
	area_rules[aid] = {"any": any_allowed, "allowed": psa}
	_enforce_area_rules(aid)

func _enforce_area_rules(aid: int) -> void:
	var cells: Array[Vector2i] = area_id_cells.get(aid, [] as Array[Vector2i])
	if cells.is_empty():
		return

	var touched: Array[Vector2i] = []

	for cell in cells:
		var bucket: Dictionary = contents.get(cell, {})
		var changed := false

		for k in bucket.keys():
			var kind := String(k)
			var cnt := int(bucket[k])
			if cnt <= 0:
				continue

			var rule: Dictionary = area_rules.get(aid, {"any": true, "allowed": PackedStringArray()})
			var any_ok := bool(rule.get("any", true))
			var psa: PackedStringArray = rule.get("allowed", PackedStringArray())

			var allowed := any_ok
			if not any_ok:
				for s in psa:
					if String(s) == kind:
						allowed = true
						break

			if not allowed:
				# spill and zero out
				spill_items.emit(cell, kind, cnt)
				bucket[kind] = 0
				changed = true

		# keep contents updated; mark cell if we changed it
		contents[cell] = bucket
		if changed:
			touched.append(cell)

	# notify only what changed (RimWorld-style), but still emit totals for HUD
	if touched.size() > 0:
		area_changed.emit(touched)           # batch for overlays that can take arrays
		for c in touched:
			cell_changed.emit(c)              # fine-grain for per-cell redraw
		inventory_changed.emit()              # if you have a totals bar relying on this

func on_assign_treasury_cell(cell: Vector2i) -> void:
	cell_changed.emit(cell)
	treasury_cells[cell] = true
	if not contents.has(cell): contents[cell] = {}
	if not reserved_per_cell_kind.has(cell): reserved_per_cell_kind[cell] = {}
	if not stack_kind.has(cell): stack_kind[cell] = ""
	_recompute_areas()

func on_unassign_treasury_cell(cell: Vector2i) -> void:
	cell_changed.emit(cell)
	# spill stored items
	if contents.has(cell):
		var bucket: Dictionary = contents[cell]
		for k in bucket.keys():
			var cnt := int(bucket[k])
			if cnt > 0:
				spill_items.emit(cell, String(k), cnt)
				bucket[k] = 0
		contents[cell] = bucket
	# clear maps
	treasury_cells.erase(cell)
	reserved_per_cell_kind.erase(cell)
	stack_kind.erase(cell)
	_recompute_areas()
	inventory_changed.emit()

func _recompute_areas() -> void:
	_prev_cell_area_id = cell_area_id.duplicate()
	cell_area_id.clear()
	area_id_cells.clear()
	var seen := {}
	var next_id := 1
	for c in treasury_cells.keys():
		if seen.has(c): continue
		var group := _flood(c)
		for cc in group:
			seen[cc] = true
			cell_area_id[cc] = next_id
		area_id_cells[next_id] = group.duplicate()
		next_id += 1
	# carry over rules from the most overlapping previous area
	var new_rules := {}
	for aid in area_id_cells.keys():
		var cells: Array[Vector2i] = area_id_cells[aid]
		var counts := {}
		for cc in cells:
			var old := int(_prev_cell_area_id.get(cc, -1))
			if old != -1:
				counts[old] = int(counts.get(old, 0)) + 1
		var picked_old := -1
		var best := -1
		for k in counts.keys():
			var v := int(counts[k])
			if v > best:
				best = v
				picked_old = int(k)
		if picked_old != -1 and area_rules.has(picked_old):
			var oldr: Dictionary = area_rules[picked_old]
			var any_ok := bool(oldr.get("any", true))
			var psa: PackedStringArray = oldr.get("allowed", PackedStringArray())
			new_rules[aid] = {"any": any_ok, "allowed": PackedStringArray(psa)}
		else:
			new_rules[aid] = {"any": true, "allowed": PackedStringArray()}
	area_rules = new_rules

func _flood(seed: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not treasury_cells.has(seed): return out
	var q: Array[Vector2i] = [seed]
	var seen := {seed: true}
	while q.size() > 0:
		var c = q.pop_front()
		out.append(c)
		for d in DIR4:
			var n = c + d
			if treasury_cells.has(n) and not seen.has(n):
				seen[n] = true
				q.append(n)
	return out

func area_cells_for(cell: Vector2i) -> Array[Vector2i]:
	var aid := int(cell_area_id.get(cell, -1))
	if aid == -1:
		return [] as Array[Vector2i]
	return (area_id_cells.get(aid, [] as Array[Vector2i])) as Array[Vector2i]

# --- deposit finding ----------------------------------------------------------
func _nearest_reachable_with_space_for(from_cell: Vector2i, kind: String) -> Variant:
	var found := false
	var best_cell := Vector2i.ZERO
	var best_steps := 0
	for key in treasury_cells.keys():
		var tcell: Vector2i = key
		if cell_free_effective_for(tcell, kind) <= 0: continue
		var path: PackedVector2Array = GridNav.find_path_cells(from_cell, tcell)
		if path.is_empty(): continue
		var steps = max(0, path.size() - 1)
		if (not found) or steps < best_steps:
			found = true
			best_steps = steps
			best_cell = tcell
	return best_cell if found else null

func find_best_deposit_cell_for_item(from_cell: Vector2i, kind: String) -> Variant:
	var seed = _nearest_reachable_with_space_for(from_cell, kind)
	if seed == null: return null
	var area: Array[Vector2i] = area_cells_for(seed)
	# 1) nearest partially filled of same kind
	var found := false
	var best := Vector2i.ZERO
	var best_steps := 0
	for c in area:
		if get_stored(c, kind) <= 0: continue
		if cell_free_effective_for(c, kind) <= 0: continue
		var p = GridNav.find_path_cells(from_cell, c)
		if p.is_empty(): continue
		var steps = max(0, p.size() - 1)
		if (not found) or steps < best_steps:
			found = true
			best_steps = steps
			best = c
	if found: return best
	# 2) nearest eligible empty/unassigned
	found = false
	for c2 in area:
		if cell_free_effective_for(c2, kind) <= 0: continue
		var p2 = GridNav.find_path_cells(from_cell, c2)
		if p2.is_empty(): continue
		var s2 = max(0, p2.size() - 1)
		if (not found) or s2 < best_steps:
			found = true
			best_steps = s2
			best = c2
	if found: return best
	# 3) global fallback
	return _nearest_reachable_with_space_for(from_cell, kind)
