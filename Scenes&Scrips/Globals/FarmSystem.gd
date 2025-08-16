extends Node

signal plot_updated(cell: Vector2i)

@export var seconds_to_mature: float = 12.0

# ---- VISUALS: crops are drawn on this TileMapLayer ----
@export var crops_layer_path: NodePath
var _crops: TileMapLayer = null

# Carrot 4-stage sprites (0..3). Set these in the Inspector.
@export var crop_source_id_carrot: int = -1
@export var crop_alt: int = 0
@export var carrot_stage0: Vector2i = Vector2i.ZERO
@export var carrot_stage1: Vector2i = Vector2i.ZERO
@export var carrot_stage2: Vector2i = Vector2i.ZERO
@export var carrot_stage3: Vector2i = Vector2i.ZERO

# plots: cell -> {crop, planted, growth, mature, auto_harvest, auto_replant, watered}
var plots: Dictionary = {}

func _ready() -> void:
	if crops_layer_path != NodePath(""):
		_crops = get_node_or_null(crops_layer_path) as TileMapLayer
	if _crops == null:
		_crops = get_tree().get_first_node_in_group("crops_layer") as TileMapLayer

# --- public API you already use ------------------------------------------------

func add_plot(cell: Vector2i) -> void:
	var p := {
		"crop": "carrot",
		"planted": true,
		"growth": 0.0,
		"mature": false,
		"auto_harvest": true,
		"auto_replant": true,
		"watered": false,   # <--- needs one water ever
	}
	plots[cell] = p
	plot_updated.emit(cell)
	_update_plot_visual(cell)
	# ask WaterSystem for exactly one water, if not yet watered
	_ensure_water(cell)

func remove_plot(cell: Vector2i) -> void:
	plots.erase(cell)
	plot_updated.emit(cell)
	if _crops != null:
		_crops.erase_cell(cell)

func has_plot(cell: Vector2i) -> bool:
	return plots.has(cell)

func get_plot(cell: Vector2i) -> Dictionary:
	return plots.get(cell, {})

func set_crop(cell: Vector2i, crop: String) -> void:
	if plots.has(cell):
		var p = plots[cell]
		p["crop"] = crop
		plots[cell] = p
		plot_updated.emit(cell)
		_update_plot_visual(cell)

func toggle_auto_harvest(cell: Vector2i) -> void:
	if plots.has(cell):
		var now: bool = not bool(plots[cell].get("auto_harvest", true))
		plots[cell]["auto_harvest"] = now
		plot_updated.emit(cell)
		if now and bool(plots[cell].get("mature", false)):
			JobManager.ensure_farm_harvest_job(cell)

func toggle_auto_replant(cell: Vector2i) -> void:
	if plots.has(cell):
		plots[cell]["auto_replant"] = not bool(plots[cell].get("auto_replant", true))
		plot_updated.emit(cell)

func on_harvest_completed(cell: Vector2i) -> int:
	if not plots.has(cell):
		return 0
	var p: Dictionary = plots[cell]
	var drop_count: int = 2
	if bool(p.get("auto_replant", true)):
		drop_count = 1
		p["planted"] = true
		p["growth"] = 0.0
		p["mature"] = false
		# stays watered forever once watered the first time
	else:
		p["planted"] = false
		p["growth"] = 0.0
		p["mature"] = false
	plots[cell] = p
	plot_updated.emit(cell)
	_update_plot_visual(cell)
	return drop_count

func plant_plot(cell: Vector2i) -> void:
	if plots.has(cell):
		var p: Dictionary = plots[cell]
		p["planted"] = true
		p["growth"] = 0.0
		p["mature"] = false
		plots[cell] = p
		plot_updated.emit(cell)
		_update_plot_visual(cell)
		_ensure_water(cell)

# Called by JobManager when the water haul to this farm finishes.
func on_water_delivered(cell: Vector2i) -> void:
	if not plots.has(cell):
		return
	var p = plots[cell]
	p["watered"] = true
	plots[cell] = p
	plot_updated.emit(cell)
	_update_plot_visual(cell)

# --- growth -------------------------------------------------------------------

func _process(delta: float) -> void:
	var matured: Array[Vector2i] = []
	for cell in plots.keys():
		var p: Dictionary = plots[cell]
		# must be planted AND watered to grow
		if not bool(p.get("planted", true)):
			continue
		if not bool(p.get("watered", false)):
			continue
		if not bool(p.get("mature", false)):
			p["growth"] = float(p.get("growth", 0.0)) + delta / seconds_to_mature
			if float(p["growth"]) >= 1.0:
				p["growth"] = 1.0
				p["mature"] = true
				matured.append(cell)
			plots[cell] = p
			_update_plot_visual(cell)
	for c in matured:
		var pp: Dictionary = plots[c]
		if bool(pp.get("auto_harvest", true)):
			JobManager.ensure_farm_harvest_job(c)

# --- helpers ------------------------------------------------------------------

func _ensure_water(cell: Vector2i) -> void:
	if not plots.has(cell):
		return
	if bool(plots[cell].get("watered", false)):
		return
	# one-shot water request; WaterSystem ensures only one in-flight per farm
	WaterSystem.request_one_shot_water_to_farm(cell)

func _update_plot_visual(cell: Vector2i) -> void:
	if _crops == null:
		return
	if not plots.has(cell):
		_crops.erase_cell(cell)
		return

	var p: Dictionary = plots[cell]
	var crop := String(p.get("crop", "carrot"))

	# Only carrot for now
	if crop != "carrot" or crop_source_id_carrot == -1:
		_crops.erase_cell(cell)
		return

	var planted := bool(p.get("planted", true))
	var watered := bool(p.get("watered", false))
	var growth := float(p.get("growth", 0.0))

	var stage := 0
	if planted and watered:
		var g = clamp(growth, 0.0, 1.0)
		if g < 0.25:
			stage = 0
		elif g < 0.5:
			stage = 1
		elif g < 0.75:
			stage = 2
		else:
			stage = 3
	else:
		stage = 0

	var atlas: Vector2i = [carrot_stage0, carrot_stage1, carrot_stage2, carrot_stage3][stage]
	_crops.set_cell(cell, crop_source_id_carrot, atlas, crop_alt)
