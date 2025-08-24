# res://Scripts/WaterTiles.gd
extends Node

var layer: TileMapLayer = null

func init(water_layer: TileMapLayer) -> void:
	layer = water_layer
	if layer == null:
		return
	for c in layer.get_used_cells():
		GridNav.astar.set_point_solid(Vector2i(c), true)

func is_water(cell: Vector2i) -> bool:
	return layer != null and layer.get_cell_source_id(cell) != -1
