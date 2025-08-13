extends Node2D
class_name JobOverlay

@export var floor_layer_path: NodePath
@export var color_dig: Color = Color(1.0, 0.35, 0.2, 0.35)     # reddish
@export var color_build: Color = Color(0.2, 0.7, 1.0, 0.35)     # blueish
@export var outline_color: Color = Color(0, 0, 0, 0.75)

var _floor: TileMapLayer = null
var _dig: Dictionary = {}      # Vector2i -> Job.Status
var _build: Dictionary = {}    # Vector2i -> Job.Status

@export var color_room_assign: Color = Color(1.0, 0.8, 0.2, 0.35)	# gold
@export var color_room_unassign: Color = Color(0.5, 0.5, 0.5, 0.35)	# gray
@export var color_farm_harvest: Color = Color(0.3, 1.0, 0.3, 0.35)
var _farm_harvest: Dictionary = {}	# cell -> Status


var _room_assign: Dictionary = {}	# cell -> Status
var _room_unassign: Dictionary = {}

@export var color_haul: Color = Color(0.6, 0.3, 1.0, 0.35)	# purple
var _haul: Dictionary = {}	# cell -> {"status": int, "kind": String}


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
	
func _on_items_changed(cell: Vector2i) -> void:
	if _haul.has(cell):
		var info: Dictionary = _haul[cell]
		var kind: String = String(info.get("kind", "rock"))
		if not JobManager.has_ground_item(cell, kind):
			_haul.erase(cell)
	queue_redraw()

func _on_job_event(job: Job) -> void:
	_update_job(job)
	queue_redraw()

func _rebuild() -> void:
	_dig.clear()
	_build.clear()
	_farm_harvest.clear()
	_room_assign.clear()
	_room_unassign.clear()
	for j: Job in JobManager.jobs:
		_update_job(j)
	queue_redraw()

func _update_job(job: Job) -> void:
	# remove ghosts for finished/cancelled jobs immediately
	if job.status == Job.Status.DONE or job.status == Job.Status.CANCELLED:
		if job.type == "dig_wall":
			_dig.erase(job.target_cell)
		elif job.type == "build_wall":
			_build.erase(job.target_cell)
		elif job.type == "assign_room":
			_room_assign.erase(job.target_cell)
		elif job.type == "unassign_room":
			_room_unassign.erase(job.target_cell)
		elif job.type.begins_with("haul_"):
			_haul.erase(job.target_cell)
		elif job.type == "farm_harvest":
			_farm_harvest.erase(job.target_cell)
		return

	# still-open jobs:
	if job.type == "dig_wall":
		_dig[job.target_cell] = job.status
		return
	elif job.type == "build_wall":
		_build[job.target_cell] = job.status
		return
	elif job.type == "assign_room":
		_room_assign[job.target_cell] = job.status
		return
	elif job.type == "farm_harvest":
		_farm_harvest[job.target_cell] = job.status
	elif job.type == "unassign_room":
		_room_unassign[job.target_cell] = job.status
		return
	elif job.type.begins_with("haul_"):
		var kind: String = String(job.data.get("kind", "rock"))
		if JobManager.has_ground_item(job.target_cell, kind):
			_haul[job.target_cell] = {"status": job.status, "kind": kind}
		else:
			_haul.erase(job.target_cell)
		return


func _draw() -> void:
	if _floor == null:
		return

	var size: Vector2 = Vector2(GridNav.cell_size)
	var half: Vector2 = size * 0.5

	for key in _haul.keys():
		var info: Dictionary = _haul[key]
		var st: int = int(info.get("status", Job.Status.OPEN))
		var ch: Color = color_haul
		if st == Job.Status.RESERVED:
			ch.a *= 0.6
		elif st == Job.Status.ACTIVE:
			ch.a *= 0.9
		_draw_cell(key, size, half, ch)

	for key in _dig.keys():
		var c: Color = color_dig
		var st: int = int(_dig[key])
		if st == Job.Status.RESERVED:
			c.a = c.a * 0.6
		elif st == Job.Status.ACTIVE:
			c.a = c.a * 0.9
		_draw_cell(key, size, half, c)

	for key in _build.keys():
		var cb: Color = color_build
		var stb: int = int(_build[key])
		if stb == Job.Status.RESERVED:
			cb.a = cb.a * 0.6
		elif stb == Job.Status.ACTIVE:
			cb.a = cb.a * 0.9
		_draw_cell(key, size, half, cb)

	for key2 in _room_assign.keys():
		var cr: Color = color_room_assign
		var str: int = int(_room_assign[key2])
		if str == Job.Status.RESERVED:
			cr.a = cr.a * 0.6
		elif str == Job.Status.ACTIVE:
			cr.a = cr.a * 0.9
		_draw_cell(key2, size, half, cr)

	for key3 in _room_unassign.keys():
		var cu: Color = color_room_unassign
		var stu: int = int(_room_unassign[key3])
		if stu == Job.Status.RESERVED:
			cu.a = cu.a * 0.6
		elif stu == Job.Status.ACTIVE:
			cu.a = cu.a * 0.9
		_draw_cell(key3, size, half, cu)
		
	for kf in _farm_harvest.keys():
		var cf: Color = color_farm_harvest
		var stf: int = int(_farm_harvest[kf])
		if stf == Job.Status.RESERVED:
			cf.a *= 0.6
		elif stf == Job.Status.ACTIVE:
			cf.a *= 0.9
		_draw_cell(kf, size, half, cf)

func _draw_cell(cell: Vector2i, size: Vector2, half: Vector2, fill: Color) -> void:
	# convert cell -> this node's local space
	var local_from_floor: Vector2 = _floor.map_to_local(cell)
	var world_pos: Vector2 = _floor.to_global(local_from_floor)
	var p: Vector2 = to_local(world_pos)

	var rect := Rect2(p - half, size)
	draw_rect(rect, fill, true)
	draw_rect(rect, outline_color, false, 1.0)
