extends Node

signal items_changed(cell: Vector2i, kind: String)

# cell(Vector2i) -> { kind(String): count(int) }
var items_on_ground: Dictionary = {}

func drop_item(cell: Vector2i, kind: String, count: int) -> void:
	var d: Dictionary = items_on_ground.get(cell, {})
	d[kind] = int(d.get(kind, 0)) + count
	items_on_ground[cell] = d
	items_changed.emit(cell, kind)

func has(cell: Vector2i, kind: String) -> bool:
	if not items_on_ground.has(cell):
		return false
	return int((items_on_ground[cell] as Dictionary).get(kind, 0)) > 0

func take(cell: Vector2i, kind: String, count: int) -> bool:
	if not has(cell, kind):
		return false
	var d: Dictionary = items_on_ground[cell]
	var cur := int(d.get(kind, 0))
	var newv = max(0, cur - count)
	d[kind] = newv
	if newv == 0:
		d.erase(kind)
	if d.size() == 0:
		items_on_ground.erase(cell)
	else:
		items_on_ground[cell] = d
	items_changed.emit(cell, kind)
	return true

func count(cell: Vector2i, kind: String) -> int:
	if not items_on_ground.has(cell):
		return 0
	return int((items_on_ground[cell] as Dictionary).get(kind, 0))
