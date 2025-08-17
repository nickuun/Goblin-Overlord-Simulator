extends CanvasLayer

signal treasury_rules_changed(cell: Vector2i, any_allowed: bool, allowed: Array[String])

var hud_label: Label
var hover_label: Label
var panel: Panel
var any_cb: CheckBox
var rock_cb: CheckBox
var carrot_cb: CheckBox
var _panel_cell: Vector2i = Vector2i.ZERO

# --- top: add nodes for new panels --------------------------------------------  # NEW
var panel_bucket: Panel
var panel_well: Panel
var panel_farm: Panel

# bucket widgets
var bucket_enabled_cb: CheckBox
var bucket_refill_slider: HSlider
var bucket_refill_label: Label
var bucket_info: Label

# well widgets
var well_enabled_cb: CheckBox
var well_info: Label

# farm widgets
var farm_crop_ob: OptionButton
var farm_auto_h_cb: CheckBox
var farm_auto_r_cb: CheckBox
var farm_info: Label
var _bucket_cell: Vector2i = Vector2i.ZERO
var _well_cell: Vector2i = Vector2i.ZERO
var _farm_cell: Vector2i = Vector2i.ZERO

@export var inspector_refresh_hz: float = 4.0
var _inspect_refresh_accum := 0.0

func _process(delta: float) -> void:
	_inspect_refresh_accum += delta
	var period = 1.0 / max(0.01, inspector_refresh_hz)
	if _inspect_refresh_accum >= period:
		_inspect_refresh_accum = 0.0
		if panel_bucket.visible: _refresh_bucket_panel()
		if panel_well.visible:   _refresh_well_panel()
		if panel_farm.visible:   _refresh_farm_panel()

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
	
		# --- Bucket Panel -----------------------------------------------------------  # NEW
	panel_bucket = Panel.new()
	panel_bucket.visible = false
	panel_bucket.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel_bucket.position = Vector2(8, 230)
	panel_bucket.custom_minimum_size = Vector2(320, 170)
	add_child(panel_bucket)

	var vbB := VBoxContainer.new()
	vbB.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbB.offset_left = 8; vbB.offset_top = 8; vbB.offset_right = -8; vbB.offset_bottom = -8
	panel_bucket.add_child(vbB)

	var tB := Label.new(); tB.text = "Bucket"
	tB.add_theme_font_size_override("font_size", 16)
	vbB.add_child(tB)

	bucket_enabled_cb = CheckBox.new()
	bucket_enabled_cb.text = "Enabled"
	bucket_enabled_cb.toggled.connect(func(on: bool):
		if WaterSystem != null and WaterSystem.bucket_cells.has(_bucket_cell):
			WaterSystem.set_bucket_enabled(_bucket_cell, on)
			_refresh_bucket_panel()
	)
	vbB.add_child(bucket_enabled_cb)

	var hb := HBoxContainer.new(); vbB.add_child(hb)
	var l := Label.new(); l.text = "Refill until:"; hb.add_child(l)
	bucket_refill_slider = HSlider.new()
	bucket_refill_slider.min_value = 0; bucket_refill_slider.max_value = 10; bucket_refill_slider.step = 1
	bucket_refill_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bucket_refill_slider.value_changed.connect(func(v):
		if WaterSystem != null and WaterSystem.bucket_cells.has(_bucket_cell):
			var new_v := int(round(v))
			var cur_v := WaterSystem.get_bucket_refill_until(_bucket_cell)
			if new_v != cur_v:
				WaterSystem.set_bucket_refill_until(_bucket_cell, new_v)
				# we don't need to force a refresh here; the tick will update it
	)
	hb.add_child(bucket_refill_slider)
	bucket_refill_label = Label.new(); bucket_refill_label.text = "0"; hb.add_child(bucket_refill_label)

	bucket_info = Label.new()
	bucket_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbB.add_child(bucket_info)

	# --- Well Panel -------------------------------------------------------------  # NEW
	panel_well = Panel.new()
	panel_well.visible = false
	panel_well.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel_well.position = Vector2(8, 410)
	panel_well.custom_minimum_size = Vector2(320, 150)
	add_child(panel_well)

	var vbW := VBoxContainer.new()
	vbW.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbW.offset_left = 8; vbW.offset_top = 8; vbW.offset_right = -8; vbW.offset_bottom = -8
	panel_well.add_child(vbW)

	var tW := Label.new(); tW.text = "Well"
	tW.add_theme_font_size_override("font_size", 16)
	vbW.add_child(tW)

	well_enabled_cb = CheckBox.new()
	well_enabled_cb.text = "Enabled"
	well_enabled_cb.toggled.connect(func(on: bool):
		if WaterSystem != null and WaterSystem.well_cells.has(_well_cell):
			WaterSystem.set_well_enabled(_well_cell, on)
			_refresh_well_panel()
	)
	vbW.add_child(well_enabled_cb)

	well_info = Label.new()
	well_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbW.add_child(well_info)

	# --- Farm Panel -------------------------------------------------------------  # NEW
	panel_farm = Panel.new()
	panel_farm.visible = false
	panel_farm.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel_farm.position = Vector2(340, 64)
	panel_farm.custom_minimum_size = Vector2(340, 220)
	add_child(panel_farm)

	var vbF := VBoxContainer.new()
	vbF.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbF.offset_left = 8; vbF.offset_top = 8; vbF.offset_right = -8; vbF.offset_bottom = -8
	panel_farm.add_child(vbF)

	var tF := Label.new(); tF.text = "Farm"
	tF.add_theme_font_size_override("font_size", 16)
	vbF.add_child(tF)

	var hbCrop := HBoxContainer.new(); vbF.add_child(hbCrop)
	var lc := Label.new(); lc.text = "Crop:"; hbCrop.add_child(lc)
	farm_crop_ob = OptionButton.new()
	# Try to list available crops if FarmSystem exposes them
	var crops := []
	if FarmSystem != null and FarmSystem.has_method("get_available_crops"):
		crops = FarmSystem.get_available_crops()
	else:
		crops = ["carrot"]
	for i in range(crops.size()):
		farm_crop_ob.add_item(String(crops[i]), i)
	farm_crop_ob.item_selected.connect(func(_idx):
		if FarmSystem != null and FarmSystem.has_plot(_farm_cell):
			var crop := farm_crop_ob.get_item_text(farm_crop_ob.get_selected_id())
			FarmSystem.set_crop(_farm_cell, crop)
			# optional: replant immediately if auto_replant on
			var p := FarmSystem.get_plot(_farm_cell)
			if bool(p.get("auto_replant", true)):
				FarmSystem.plant_plot(_farm_cell)
		_refresh_farm_panel()
	)
	hbCrop.add_child(farm_crop_ob)

	farm_auto_h_cb = CheckBox.new(); farm_auto_h_cb.text = "Auto harvest"
	farm_auto_h_cb.toggled.connect(func(on: bool):
		if FarmSystem != null: FarmSystem.set_auto_harvest(_farm_cell, on) if FarmSystem.has_method("set_auto_harvest") else FarmSystem.toggle_auto_harvest(_farm_cell)
		_refresh_farm_panel()
	)
	vbF.add_child(farm_auto_h_cb)

	farm_auto_r_cb = CheckBox.new(); farm_auto_r_cb.text = "Auto replant"
	farm_auto_r_cb.toggled.connect(func(on: bool):
		if FarmSystem != null: FarmSystem.set_auto_replant(_farm_cell, on) if FarmSystem.has_method("set_auto_replant") else FarmSystem.toggle_auto_replant(_farm_cell)
		_refresh_farm_panel()
	)
	vbF.add_child(farm_auto_r_cb)

	farm_info = Label.new()
	farm_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbF.add_child(farm_info)
	
	# Default positions (rough), then clamp once:
	panel.position = Vector2(8, 64)
	panel_bucket.position = Vector2(8, 230)
	panel_well.position   = Vector2(8, 410)
	panel_farm.position   = Vector2(340, 64)
	_layout_static_panels()

	# Relayout on resize
	get_viewport().connect("size_changed", Callable(self, "_layout_static_panels"))

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

# --- panel API -----------------------------------------------------------------  # NEW
func hide_all_panels() -> void:
	panel.visible = false
	panel_bucket.visible = false
	panel_well.visible = false
	panel_farm.visible = false

func show_bucket_config(cell: Vector2i) -> void:
	_bucket_cell = cell
	panel.visible = false
	panel_well.visible = false
	panel_farm.visible = false
	panel_bucket.visible = true
	_place_control_on_screen(panel_bucket, panel_bucket.position)  # clamp now
	_refresh_bucket_panel()

func show_well_config(cell: Vector2i) -> void:
	_well_cell = cell
	panel.visible = false
	panel_bucket.visible = false
	panel_farm.visible = false
	panel_well.visible = true
	_place_control_on_screen(panel_well, panel_well.position)
	_refresh_well_panel()

func show_farm_config(cell: Vector2i) -> void:
	_farm_cell = cell
	panel.visible = false
	panel_bucket.visible = false
	panel_well.visible = false
	panel_farm.visible = true
	_place_control_on_screen(panel_farm, panel_farm.position)
	_refresh_farm_panel()

func _refresh_bucket_panel() -> void:
	if WaterSystem == null or not WaterSystem.bucket_cells.has(_bucket_cell): return
	var d := WaterSystem.get_bucket_inspect_data(_bucket_cell)
	var cap := int(d.get("capacity", 0))
	bucket_enabled_cb.set_pressed_no_signal(bool(d.get("enabled", true)))
	bucket_refill_slider.max_value = cap * 1.0
	bucket_refill_slider.set_value_no_signal(int(d.get("refill_until", cap)))
	bucket_refill_label.text = "%d / %d" % [int(d.get("refill_until", cap)), cap]
	var wells: Array = d.get("incoming_from_wells", [])
	var farms: Array = d.get("serving_farms", [])
	bucket_info.text = "Stored: %d/%d  (in:+%d out:-%d)\nFrom wells: %s\nServing farms: %s" % [
		int(d.get("stored",0)), cap, int(d.get("incoming",0)), int(d.get("outgoing",0)),
		_vector_list(wells), _vector_list(farms)
	]

func _refresh_well_panel() -> void:
	if WaterSystem == null or not WaterSystem.well_cells.has(_well_cell): return
	var d := WaterSystem.get_well_inspect_data(_well_cell)
	well_enabled_cb.set_pressed_no_signal(bool(d.get("enabled", true)))
	var wb: Array = d.get("waiting_buckets", [])
	var wf: Array = d.get("waiting_farms", [])
	well_info.text = "Pile: %d\nWaiting buckets: %s\nWaiting farms: %s" % [
		int(d.get("pile",0)), _vector_list(wb), _vector_list(wf)
	]

func _refresh_farm_panel() -> void:
	if FarmSystem == null or not FarmSystem.has_plot(_farm_cell): return
	var p := FarmSystem.get_plot(_farm_cell)
	# set crop dropdown
	var crop := String(p.get("crop","carrot"))
	for i in range(farm_crop_ob.item_count):
		if farm_crop_ob.get_item_text(i) == crop:
			farm_crop_ob.select(i); break
	farm_auto_h_cb.set_pressed_no_signal(bool(p.get("auto_harvest", true)))
	farm_auto_r_cb.set_pressed_no_signal(bool(p.get("auto_replant", true)))
	var watered := bool(p.get("watered", false))
	var stage := String(p.get("stage", "seed"))
	var growth := float(p.get("growth", 0.0))    # 0..1 if you expose it
	var eta_s := float(p.get("eta_s", -1.0))     # seconds to ready if you expose it
	var growth_txt := "%d%%" % int(round(growth * 100.0))
	var eta_txt := (str(int(round(eta_s))) + "s") if eta_s >= 0.0 else "—"
	farm_info.text = "Stage: %s\nWatered: %s\nGrowth: %s\nETA: %s" % [stage, str(watered), growth_txt, eta_txt]

func _vector_list(arr: Array) -> String:
	var s := []
	for v in arr: s.append("(%d,%d)" % [Vector2i(v).x, Vector2i(v).y])
	return ", ".join(s) if s.size() > 0 else "—"

# --- add helpers near top/bottom of file
func _place_control_on_screen(c: Control, wanted_pos: Vector2) -> void:
	var vp = get_tree().root.get_visible_rect().size
	var min_size := c.get_combined_minimum_size()
	var x = clamp(wanted_pos.x, 8.0, vp.x - min_size.x - 8.0)
	var y = clamp(wanted_pos.y, 8.0, vp.y - min_size.y - 8.0)
	c.position = Vector2(x, y)

func _layout_static_panels() -> void:
	# keep HUD + hover where they were
	_place_control_on_screen(panel, panel.position)
	_place_control_on_screen(panel_bucket, panel_bucket.position)
	_place_control_on_screen(panel_well, panel_well.position)
	_place_control_on_screen(panel_farm, panel_farm.position)
