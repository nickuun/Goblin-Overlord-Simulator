extends Node2D
class_name JobOverlay

@export var floor_layer_path: NodePath

# --- Colors --------------------------------------------------------------
@export var color_dig: Color = Color(1.0, 0.35, 0.2, 0.35)      # reddish
@export var color_build: Color = Color(0.2, 0.7, 1.0, 0.35)      # blueish
@export var color_room_assign: Color = Color(1.0, 0.8, 0.2, 0.35)# gold
@export var color_room_unassign: Color = Color(0.5, 0.5, 0.5, 0.35)# gray
@export var color_farm_harvest: Color = Color(0.3, 1.0, 0.3, 0.35)
@export var color_haul: Color = Color(0.6, 0.3, 1.0, 0.35)       # purple (generic)
@export var color_haul_water_bucket: Color = Color(0.3, 0.9, 1.0, 0.45) # water from bucket
@export var color_place_furniture: Color = Color(0.4, 0.6, 1.0, 0.35)
@export var color_well_operate: Color = Color(0.2, 0.9, 1.0, 0.35)
@export var outline_color: Color = Color(0, 0, 0, 0.75)

# --- Data buckets --------------------------------------------------------
var _floor: TileMapLayer = null

var _dig: Dictionary = {}            # cell -> Status
var _build: Dictionary = {}          # cell -> Status
var _room_assign: Dictionary = {}    # cell -> Status
var _room_unassign: Dictionary = {}  # cell -> Status
var _farm_harvest: Dictionary = {}   # cell -> Status
var _place_furniture: Dictionary = {}# cell -> Status
var _well_operate: Dictionary = {}   # cell -> Status

# Haul overlay: cell(source) -> {status:int, kind:String, source:String("","bucket","ground"), deposit_target:String("","bucket","farm")}
var _haul: Dictionary = {}

# --- Setup -------------------------------------------------------------------
func _ready() -> void:
	JobManager.items_changed.connect(_on_items_changed)

	if floor_layer_path != NodePath(""):
		_floor = get_node_or_null(floor_layer_path) as TileMapLayer
	if _floor == null:
		_floor = get_tree().get_first_node_in_group("floor_layer") as TileMapLayer
	if _floor == null:
		push_error("JobOverlay: no Floor TileMapLayer set (path or 'floor_layer' group).")
		return

	z_as_relative = false
	z_index = 100

	JobManager.job_added.connect(_on_job_event)
	JobManager.job_updated.connect(_on_job_event)
	JobManager.job_completed.connect(_on_job_event)

	_rebuild()

# Ground items changed: prune haul jobs that depended on ground items at that cell.
# IMPORTANT: do NOT prune water hauls whose source is a BUCKET (no ground items there).
func _on_items_changed(cell: Vector2i) -> void:
	if _haul.has(cell):
		var info: Dictionary = _haul[cell]
		var kind: String = String(info.get("kind", "rock"))
		var src := String(info.get("source", ""))  # "bucket" or "ground" or ""
		# only auto-remove if this haul depends on ground items at source
		if not (kind == "water" and src == "bucket"):
			if not JobManager.has_ground_item(cell, kind):
				_haul.erase(cell)
	queue_redraw()

func _on_job_event(job: Job) -> void:
	_update_job(job)
	queue_redraw()

func _rebuild() -> void:
	_dig.clear()
	_build.clear()
	_room_assign.clear()
	_room_unassign.clear()
	_farm_harvest.clear()
	_place_furniture.clear()
	_well_operate.clear()
	_haul.clear()
	for j: Job in JobManager.jobs:
		_update_job(j)
	queue_redraw()

# Keep exactly one rectangle per job “type@cell”.
# For hauls, we draw at the SOURCE cell (job.target_cell), since that’s where the pickup happens.
func _update_job(job: Job) -> void:
	# clear immediately for done/cancelled
	if job.status == Job.Status.DONE or job.status == Job.Status.CANCELLED:
		match job.type:
			"dig_wall": _dig.erase(job.target_cell)
			"build_wall": _build.erase(job.target_cell)
			"place_furniture": _place_furniture.erase(job.target_cell)
			"well_operate": _well_operate.erase(job.target_cell)
			"assign_room": _room_assign.erase(job.target_cell)
			"unassign_room": _room_unassign.erase(job.target_cell)
			"farm_harvest": _farm_harvest.erase(job.target_cell)
			_:
				if job.type.begins_with("haul_"):
					_haul.erase(job.target_cell)
		return

	# still-open jobs
	match job.type:
		"dig_wall":
			_dig[job.target_cell] = job.status
			return
		"build_wall":
			_build[job.target_cell] = job.status
			return
		"place_furniture":
			_place_furniture[job.target_cell] = job.status
			return
		"well_operate":
			_well_operate[job.target_cell] = job.status
			return
		"assign_room":
			_room_assign[job.target_cell] = job.status
			return
		"unassign_room":
			_room_unassign[job.target_cell] = job.status
			return
		"farm_harvest":
			_farm_harvest[job.target_cell] = job.status
			return
		_:
			if job.type.begins_with("haul_"):
				var kind: String = String(job.data.get("kind", "rock"))
				var src: String = String(job.data.get("source", ""))  # "bucket" or "ground" (WaterSystem sets this)
				var deposit_target: String = String(job.data.get("deposit_target", "")) # "", "bucket", "farm"

				# Show logic:
				# - water from BUCKET: always draw (no ground pile to check)
				# - any other haul: only draw if a ground item is present at source
				var should_show := true
				if not (kind == "water" and src == "bucket"):
					should_show = JobManager.has_ground_item(job.target_cell, kind)

				if should_show:
					_haul[job.target_cell] = {
						"status": job.status,
						"kind": kind,
						"source": src,
						"deposit_target": deposit_target
					}
				else:
					_haul.erase(job.target_cell)
				return

# --- Draw ---------------------------------------------------------------------
func _draw() -> void:
	if _floor == null:
		return

	var size: Vector2 = Vector2(GridNav.cell_size)
	var half: Vector2 = size * 0.5

	# Hauls (choose color by type/source)
	for cell in _haul.keys():
		var info: Dictionary = _haul[cell]
		var st: int = int(info.get("status", Job.Status.OPEN))
		var kind := String(info.get("kind", "rock"))
		var src := String(info.get("source", ""))              # "bucket" or "ground"
		var dst := String(info.get("deposit_target", ""))      # "", "bucket", "farm"

		var ch: Color = color_haul
		if kind == "water" and src == "bucket":
			ch = color_haul_water_bucket

		if st == Job.Status.RESERVED:
			ch.a *= 0.6
		elif st == Job.Status.ACTIVE:
			ch.a *= 0.9
		_draw_cell(cell, size, half, ch)

	# Digs
	for c in _dig.keys():
		var col := color_dig
		var st := int(_dig[c])
		if st == Job.Status.RESERVED: col.a *= 0.6
		elif st == Job.Status.ACTIVE: col.a *= 0.9
		_draw_cell(c, size, half, col)

	# Builds
	for c2 in _build.keys():
		var col2 := color_build
		var st2 := int(_build[c2])
		if st2 == Job.Status.RESERVED: col2.a *= 0.6
		elif st2 == Job.Status.ACTIVE: col2.a *= 0.9
		_draw_cell(c2, size, half, col2)

	# Room assign / unassign
	for c3 in _room_assign.keys():
		var col3 := color_room_assign
		var st3 := int(_room_assign[c3])
		if st3 == Job.Status.RESERVED: col3.a *= 0.6
		elif st3 == Job.Status.ACTIVE: col3.a *= 0.9
		_draw_cell(c3, size, half, col3)

	for c4 in _room_unassign.keys():
		var col4 := color_room_unassign
		var st4 := int(_room_unassign[c4])
		if st4 == Job.Status.RESERVED: col4.a *= 0.6
		elif st4 == Job.Status.ACTIVE: col4.a *= 0.9
		_draw_cell(c4, size, half, col4)

	# Place furniture
	for c5 in _place_furniture.keys():
		var col5 := color_place_furniture
		var st5 := int(_place_furniture[c5])
		if st5 == Job.Status.RESERVED: col5.a *= 0.6
		elif st5 == Job.Status.ACTIVE: col5.a *= 0.9
		_draw_cell(c5, size, half, col5)

	# Well operate
	for c6 in _well_operate.keys():
		var col6 := color_well_operate
		var st6 := int(_well_operate[c6])
		if st6 == Job.Status.RESERVED: col6.a *= 0.6
		elif st6 == Job.Status.ACTIVE: col6.a *= 0.9
		_draw_cell(c6, size, half, col6)

	# Farm harvest
	for c7 in _farm_harvest.keys():
		var col7 := color_farm_harvest
		var st7 := int(_farm_harvest[c7])
		if st7 == Job.Status.RESERVED: col7.a *= 0.6
		elif st7 == Job.Status.ACTIVE: col7.a *= 0.9
		_draw_cell(c7, size, half, col7)

func _draw_cell(cell: Vector2i, size: Vector2, half: Vector2, fill: Color) -> void:
	var local_from_floor: Vector2 = _floor.map_to_local(cell)
	var world_pos: Vector2 = _floor.to_global(local_from_floor)
	var p: Vector2 = to_local(world_pos)

	var rect := Rect2(p - half, size)
	draw_rect(rect, fill, true)
	draw_rect(rect, outline_color, false, 1.0)
