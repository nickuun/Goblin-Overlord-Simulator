extends CanvasLayer

signal treasury_rules_changed(cell: Vector2i, any_allowed: bool, allowed: Array[String])

var hud_label: Label
var hover_label: Label
var panel: Panel
var any_cb: CheckBox
var rock_cb: CheckBox
var carrot_cb: CheckBox
var _panel_cell: Vector2i = Vector2i.ZERO

func _ready() -> void:
	# HUD root
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# --- Inventory HUD (top-left) ---
	hud_label = Label.new()
	hud_label.text = "Inventory: -"
	hud_label.add_theme_font_size_override("font_size", 18)
	hud_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hud_label.position = Vector2(8, 8)
	root.add_child(hud_label)

	# --- Hover readout (under HUD) ---
	hover_label = Label.new()
	hover_label.text = ""
	hover_label.add_theme_font_size_override("font_size", 16)
	hover_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hover_label.position = Vector2(8, 32)
	root.add_child(hover_label)

	# --- Panel (area rules) ---
	panel = Panel.new()
	panel.visible = false
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(8, 64)
	panel.custom_minimum_size = Vector2(260, 160)
	add_child(panel)

	# Fill panel with padded VBox
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 8
	vb.offset_top = 8
	vb.offset_right = -8
	vb.offset_bottom = -8
	panel.add_child(vb)

	var title := Label.new()
	title.text = "Treasury Rules (area)"
	title.add_theme_font_size_override("font_size", 16)
	vb.add_child(title)

	any_cb = CheckBox.new()
	any_cb.text = "Any"
	any_cb.toggled.connect(_on_any_toggled)
	vb.add_child(any_cb)

	rock_cb = CheckBox.new()
	rock_cb.text = "Rock"
	rock_cb.toggled.connect(_on_kind_toggled.bind("rock"))
	vb.add_child(rock_cb)

	carrot_cb = CheckBox.new()
	carrot_cb.text = "Carrot"
	carrot_cb.toggled.connect(_on_kind_toggled.bind("carrot"))
	vb.add_child(carrot_cb)

	# Listen for inventory changes (autoload singletons can be accessed directly if added)
	if has_node("/root/JobManager"):
		JobManager.inventory_changed.connect(_on_inventory_changed)
	_on_inventory_changed()

func _on_inventory_changed() -> void:
	if not Engine.has_singleton("JobManager"):
		return
	var totals = JobManager.get_inventory_totals()
	var r := int(totals.get("rock", 0))
	var c := int(totals.get("carrot", 0))
	hud_label.text = "Inventory: Rock %d | Carrot %d" % [r, c]

func set_hover_text(text: String) -> void:
	hover_label.text = text

func show_treasury_config(cell: Vector2i, _any_allowed: bool, _allowed: Array[String]) -> void:
	_panel_cell = cell
	panel.visible = true

	var rules := JobManager.get_treasury_rules_for_cell(cell)
	var any_allowed := bool(rules.get("any", true))
	var allowed_any: Array = rules.get("allowed", [])
	var allowed: Array[String] = []
	for k in allowed_any:
		allowed.append(String(k))

	any_cb.set_pressed_no_signal(any_allowed)

	var allow_rock := any_allowed or allowed.has("rock")
	var allow_carrot := any_allowed or allowed.has("carrot")

	rock_cb.disabled = any_allowed
	carrot_cb.disabled = any_allowed
	rock_cb.set_pressed_no_signal(allow_rock and not any_allowed)
	carrot_cb.set_pressed_no_signal(allow_carrot and not any_allowed)

func hide_treasury_config() -> void:
	panel.visible = false

func _on_any_toggled(pressed: bool) -> void:
	rock_cb.disabled = pressed
	carrot_cb.disabled = pressed
	var al: Array[String] = []
	if not pressed:
		if rock_cb.button_pressed:
			al.append("rock")
		if carrot_cb.button_pressed:
			al.append("carrot")
	treasury_rules_changed.emit(_panel_cell, pressed, al)

func _on_kind_toggled(pressed: bool, kind: String) -> void:
	if any_cb.button_pressed:
		return
	var al: Array[String] = []
	if rock_cb.button_pressed:
		al.append("rock")
	if carrot_cb.button_pressed:
		al.append("carrot")
	treasury_rules_changed.emit(_panel_cell, false, al)
