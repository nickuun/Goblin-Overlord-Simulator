extends Node

signal plot_updated(cell: Vector2i)

@export var seconds_to_mature: float = 12.0

var plots: Dictionary = {}	# cell -> {crop:String, growth:float, mature:bool, auto_harvest:bool, auto_replant:bool}

func add_plot(cell: Vector2i) -> void:
	var p := {}
	p["crop"] = "carrot"
	p["growth"] = 0.0
	p["mature"] = false
	p["auto_harvest"] = true
	p["auto_replant"] = true
	plots[cell] = p
	plot_updated.emit(cell)

func remove_plot(cell: Vector2i) -> void:
	plots.erase(cell)
	plot_updated.emit(cell)

func has_plot(cell: Vector2i) -> bool:
	return plots.has(cell)

func get_plot(cell: Vector2i) -> Dictionary:
	return plots.get(cell, {})

func set_crop(cell: Vector2i, crop: String) -> void:
	if plots.has(cell):
		plots[cell]["crop"] = crop
		plot_updated.emit(cell)

func toggle_auto_harvest(cell: Vector2i) -> void:
	if plots.has(cell):
		var now: bool = not bool(plots[cell]["auto_harvest"])
		plots[cell]["auto_harvest"] = now
		plot_updated.emit(cell)
		# if it is already mature and we just turned it on, queue a job now
		if now and bool(plots[cell].get("mature", false)):
			JobManager.ensure_farm_harvest_job(cell)


func toggle_auto_replant(cell: Vector2i) -> void:
	if plots.has(cell):
		plots[cell]["auto_replant"] = not bool(plots[cell]["auto_replant"])
		plot_updated.emit(cell)

func on_harvest_completed(cell: Vector2i) -> int:
	if not plots.has(cell):
		return 0
	var p: Dictionary = plots[cell]
	var drop_count: int = 2
	if bool(p.get("auto_replant", true)):
		drop_count -= 1
		p["growth"] = 0.0
		p["mature"] = false
	else:
		p["growth"] = 0.0
		p["mature"] = false
	plots[cell] = p
	plot_updated.emit(cell)
	return drop_count

func _process(delta: float) -> void:
	var matured: Array[Vector2i] = []
	for cell in plots.keys():
		var p: Dictionary = plots[cell]
		if not bool(p.get("mature", false)):
			p["growth"] = float(p.get("growth", 0.0)) + delta / seconds_to_mature
			if float(p["growth"]) >= 1.0:
				p["growth"] = 1.0
				p["mature"] = true
				matured.append(cell)
			plots[cell] = p
	for c in matured:
		var pp: Dictionary = plots[c]
		if bool(pp.get("auto_harvest", true)):
			JobManager.ensure_farm_harvest_job(c)
