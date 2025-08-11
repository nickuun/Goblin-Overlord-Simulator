extends Camera2D

# -------- Tunables --------
@export var max_speed: float = 600.0              # top panning speed (world px/sec) — a bit slower than before
@export var accel: float = 4000.0                 # how quickly you ramp up to speed
@export var decel: float = 5000.0                 # how quickly you slow down

@export var smoothing_speed: float = 12.0         # camera follow smoothness (higher = snappier)
@export var zoom_smoothing_speed: float = 6.0     # zoom smoothness (lower -> slower, more deliberate)

@export var zoom_step: float = 0.1                # Q/E step size
@export var min_zoom: float = 0.6                 # further out
@export var max_zoom: float = 2.5                 # further in

@export var pixel_snap_enabled: bool = true
@export var speed_compensate_by_zoom: bool = true # keep pan feel consistent when zoomed in/out

# -------- Internals --------
var _target_pos: Vector2
var _target_zoom: float
var _velocity: Vector2 = Vector2.ZERO

func _ready() -> void:
	_target_pos = global_position
	_target_zoom = zoom.x  # we use uniform zoom (x == y)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cam_zoom_in"):
		_target_zoom = max(min_zoom, _target_zoom - zoom_step)
	elif event.is_action_pressed("cam_zoom_out"):
		_target_zoom = min(max_zoom, _target_zoom + zoom_step)

func _process(delta: float) -> void:
	# -------- Input → desired velocity with accel/decel --------
	var dir: Vector2 = Vector2(
		Input.get_action_strength("cam_right") - Input.get_action_strength("cam_left"),
		Input.get_action_strength("cam_down") - Input.get_action_strength("cam_up")
	)

	# Optional: adjust speed to feel similar across zoom levels
	var zoom_factor: float = 1.0
	if speed_compensate_by_zoom:
		# smaller zoom (zoomed out) -> smaller factor; zoomed in -> bigger factor
		zoom_factor = 1.0 / max(0.001, _target_zoom)

	var target_speed: float = max_speed * zoom_factor

	if dir != Vector2.ZERO:
		dir = dir.normalized()
		var desired_velocity: Vector2 = dir * target_speed
		_velocity = _velocity.move_toward(desired_velocity, accel * delta)
	else:
		_velocity = _velocity.move_toward(Vector2.ZERO, decel * delta)

	_target_pos += _velocity * delta

	# -------- Smooth position & zoom --------
	var t_pos: float = 1.0 - pow(0.001, smoothing_speed * delta)
	global_position = global_position.lerp(_target_pos, t_pos)

	var t_zoom: float = 1.0 - pow(0.001, zoom_smoothing_speed * delta)
	var new_zoom: float = lerp(zoom.x, _target_zoom, t_zoom)
	zoom = Vector2(new_zoom, new_zoom)

	# -------- Pixel snap --------
	if pixel_snap_enabled:
		global_position = global_position.round()
