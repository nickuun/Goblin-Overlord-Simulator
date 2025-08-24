extends Control

@onready var overlay: ColorRect = $Overlay

# Editable gradient in the inspector
@export var gradient: Gradient

var _grad_tex: GradientTexture1D

func _ready() -> void:
	if self is Control:
		(self as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		(self as Control).focus_mode = Control.FOCUS_NONE

	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.focus_mode = Control.FOCUS_NONE
	# Create a gradient texture for the shader
	if gradient == null:
		gradient = _make_default_gradient()
	_grad_tex = GradientTexture1D.new()
	_grad_tex.gradient = gradient

	var mat := overlay.material as ShaderMaterial
	mat.set_shader_parameter("gradient_tex", _grad_tex)

	# Initial push & connect for updates
	_update_time(true)
	TimeManager.ten_minute_tick.connect(_update_time)
	set_process(true) # smooth interpolation between ticks

func _process(_delta: float) -> void:
	# Smoothly interpolate time to avoid visible jumps each 10 minutes
	_update_time(true)

func _update_time(smooth: bool = false) -> void:
	var comps := TimeManager.get_clock_components()
	var t := float(comps.hour * 60 + comps.minute) / float(TimeManager.MINUTES_PER_DAY)

	var mat := overlay.material as ShaderMaterial
	if smooth:
		var cur: float = mat.get_shader_parameter("time_norm")
		# wrap-aware interpolation across 0..1 seam
		var diff := t - cur
		if abs(diff) > 0.5:
			if diff > 0.0:
				cur += 1.0
			else:
				t += 1.0
		t = lerp(cur, t, 0.08)
		t = fposmod(t, 1.0) # bring back to 0..1
	mat.set_shader_parameter("time_norm", t)

func _make_default_gradient() -> Gradient:
	var g := Gradient.new()
	# Keys: (offset, color RGBA). Alpha controls strength of the tint.
	# Night -> Dawn -> Noon -> Dusk -> Night
	g.add_point(0.00, Color(0.02, 0.06, 0.12, 0.70)) # deep night
	g.add_point(0.20, Color(0.90, 0.55, 0.30, 0.35)) # warm dawn
	g.add_point(0.50, Color(1.00, 1.00, 1.00, 0.00)) # clear noon (no tint)
	g.add_point(0.80, Color(0.95, 0.45, 0.25, 0.40)) # sunset
	g.add_point(1.00, Color(0.02, 0.06, 0.12, 0.70)) # loop to night
	return g
