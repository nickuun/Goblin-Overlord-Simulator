# res://Scripts/ClickInput.gd
extends Node2D
class_name ClickInput

@export var floor_layer_path: NodePath
@export var walls_layer_path: NodePath

var _floor: TileMapLayer
var _walls: TileMapLayer

var _is_dragging: bool = false
var _drag_button: int = 0
var _drag_start: Vector2i
var _drag_ctrl: bool = false
var _drag_shift: bool = false
var _drag_prev: Vector2i

const MODE_INSPECT: int = 0
const MODE_BUILD: int = 1
const MODE_ROOM: int = 2
const MODE_SWEEP: int = 3
const MODE_FURNITURE: int = 4
var _mode: int = MODE_BUILD

var _furniture_kinds: Array[String] = ["well", "bucket"]
var _furniture_kind_index: int = 0

var _room_kinds: Array[String] = ["treasury", "farm"]
var _room_kind_index: int = 0

func _ready() -> void:
	_floor = null
	if floor_layer_path != NodePath(""):
		_floor = get_node_or_null(floor_layer_path) as TileMapLayer
	if _floor == null:
		_floor = get_tree().get_first_node_in_group("floor_layer") as TileMapLayer

	_walls = null
	if walls_layer_path != NodePath(""):
		_walls = get_node_or_null(walls_layer_path) as TileMapLayer
	if _walls == null:
		_walls = get_tree().get_first_node_in_group("wall_layer") as TileMapLayer

	if _floor == null or _walls == null:
		push_error("ClickInput: Floor or Walls layer not set. Assign NodePaths or add nodes to 'floor_layer' / 'wall_layer' groups.")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _mode == MODE_INSPECT:
		var cell := GridNav.world_to_cell(get_global_mouse_position(), _floor)
		var info = JobManager.get_cell_inspect_text(cell)
		DevUI.set_hover_text(info)

	if event is InputEventKey and event.pressed:
		var kev: InputEventKey = event
		if kev.keycode == KEY_4:
			_mode = MODE_FURNITURE
			print("Mode: FURNITURE (", _furniture_kinds[_furniture_kind_index], ")")
		elif kev.keycode == KEY_UP and _mode == MODE_FURNITURE:
			_furniture_kind_index = (_furniture_kind_index + 1) % _furniture_kinds.size()
			print("Furniture -> ", _furniture_kinds[_furniture_kind_index])
		if kev.keycode == KEY_0:
			_mode = MODE_INSPECT
			print("Mode: INSPECT")
		elif kev.keycode == KEY_1:
			_mode = MODE_BUILD
			print("Mode: BUILD")
		elif kev.keycode == KEY_2:
			_mode = MODE_ROOM
			print("Mode: ROOM (", _room_kinds[_room_kind_index], ")")
		elif kev.keycode == KEY_3:
			_mode = MODE_SWEEP
			print("Mode: SWEEP")
		elif kev.keycode == KEY_UP and _mode == MODE_ROOM:
			_room_kind_index = (_room_kind_index + 1) % _room_kinds.size()
			print("Room kind -> ", _room_kinds[_room_kind_index])
		elif kev.keycode == KEY_C and _mode == MODE_INSPECT:
			var cellc: Vector2i = GridNav.world_to_cell(get_global_mouse_position(), _floor)
			if FarmSystem.has_plot(cellc):
				FarmSystem.set_crop(cellc, "carrot")
				FarmSystem.plant_plot(cellc)	# ensure it’s planted again
				print("Planted carrot at ", cellc)

	if event is InputEventMouseButton:
		var ev: InputEventMouseButton = event
		if ev.button_index == MOUSE_BUTTON_LEFT or ev.button_index == MOUSE_BUTTON_RIGHT:
			if ev.pressed:
				_is_dragging = true
				_drag_button = ev.button_index
				_drag_ctrl = ev.ctrl_pressed
				_drag_shift = ev.shift_pressed
				_drag_start = GridNav.world_to_cell(get_global_mouse_position(), _floor)
				_drag_prev = _drag_start
				# apply to the first cell immediately
				_apply_cell_action(_drag_start)
			else:
				_is_dragging = false

	elif event is InputEventMouseMotion:
		if _is_dragging:
			var cell_now: Vector2i = GridNav.world_to_cell(get_global_mouse_position(), _floor)
			if _drag_ctrl:
				# rectangle paint/erase (kept as-is)
				_apply_rect(_drag_start, cell_now)
			else:
				# snake along the mouse path: only paint/erase the segment from the last cell to the current
				if cell_now != _drag_prev:
					var seg: Array[Vector2i] = _bresenham(_drag_prev, cell_now)
					for c: Vector2i in seg:
						_apply_cell_action(c)
					_drag_prev = cell_now

func _apply_drag_to(cell_now: Vector2i) -> void:
	if _drag_ctrl:
		_apply_rect(_drag_start, cell_now)
	else:
		_apply_line(_drag_start, cell_now)

func _apply_line(a: Vector2i, b: Vector2i) -> void:
	var cells: Array[Vector2i] = _bresenham(a, b)
	for c: Vector2i in cells:
		_apply_cell_action(c)

func _apply_rect(a: Vector2i, b: Vector2i) -> void:
	var minx: int = min(a.x, b.x)
	var maxx: int = max(a.x, b.x)
	var miny: int = min(a.y, b.y)
	var maxy: int = max(a.y, b.y)
	for y in range(miny, maxy + 1):
		for x in range(minx, maxx + 1):
			_apply_cell_action(Vector2i(x, y))

func _apply_cell_action(cell: Vector2i) -> void:
	if _mode == MODE_BUILD:
		if _drag_button == MOUSE_BUTTON_LEFT:
			if _drag_shift:
				JobManager.remove_job_at(cell, "dig_wall")
			else:
				JobManager.ensure_dig_job(cell)
		elif _drag_button == MOUSE_BUTTON_RIGHT:
			if _drag_shift:
				JobManager.remove_job_at(cell, "build_wall")
			else:
				JobManager.ensure_build_job(cell)

	elif _mode == MODE_ROOM:
		var kind: String = _room_kinds[_room_kind_index]
		if _drag_button == MOUSE_BUTTON_RIGHT:
			if _drag_shift:
				JobManager.remove_room_job_at(cell)
			else:
				JobManager.ensure_assign_room_job(cell, kind)
		elif _drag_button == MOUSE_BUTTON_LEFT:
			if _drag_shift:
				JobManager.remove_room_job_at(cell)
			else:
				JobManager.ensure_unassign_room_job(cell)
				
	elif _mode == MODE_FURNITURE:
		if _drag_button == MOUSE_BUTTON_RIGHT:
			var kind: String = _furniture_kinds[_furniture_kind_index]
			JobManager.ensure_place_furniture_job(cell, kind)
		# (optional) left-click could later remove/rotate furniture


	elif _mode == MODE_SWEEP:
		if _drag_button == MOUSE_BUTTON_RIGHT:
			if _drag_shift:
				JobManager.remove_haul_job_at(cell)
			else:
				JobManager.ensure_haul_job(cell, "rock")	# rocks (you can add carrots too)
		elif _drag_button == MOUSE_BUTTON_LEFT:
			JobManager.remove_haul_job_at(cell)

	elif _mode == MODE_INSPECT:
		if _drag_button == MOUSE_BUTTON_LEFT:
			if JobManager.is_treasury_cell(cell):
				var rules := JobManager.get_treasury_rules_for_cell(cell)
				var any_allowed := bool(rules.get("any", true))

				var allowed_any: Array = rules.get("allowed", [])
				var allowed: Array[String] = []
				for k in allowed_any:
					allowed.append(String(k))

				DevUI.show_treasury_config(cell, any_allowed, allowed)

			else:
				DevUI.hide_treasury_config()
		elif _drag_button == MOUSE_BUTTON_RIGHT:
			DevUI.hide_treasury_config()
		if FarmSystem.has_plot(cell):
			if _drag_button == MOUSE_BUTTON_LEFT:
				FarmSystem.toggle_auto_harvest(cell)
				var p := FarmSystem.get_plot(cell)
				print("Farm ", cell, ": auto_harvest=", p.get("auto_harvest", true))
			elif _drag_button == MOUSE_BUTTON_RIGHT:
				FarmSystem.toggle_auto_replant(cell)
				var p2 := FarmSystem.get_plot(cell)
				print("Farm ", cell, ": auto_replant=", p2.get("auto_replant", true))

func _bresenham(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	var x0: int = a.x
	var y0: int = a.y
	var x1: int = b.x
	var y1: int = b.y
	var dx: int = abs(x1 - x0)
	var dy: int = -abs(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx + dy
	while true:
		points.append(Vector2i(x0, y0))
		if x0 == x1 and y0 == y1:
			break
		var e2: int = 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy
	return points
