# res://Scripts/GridNav.gd
extends Node

var astar: AStarGrid2D = AStarGrid2D.new()
var cell_size: Vector2i
var origin: Vector2

# res://Scripts/GridNav.gd (only the bits that changed)
func build_from_layers(floor: TileMapLayer, walls: TileMapLayer) -> void:
	cell_size = Vector2i(floor.tile_set.tile_size)
	astar.cell_size = Vector2(cell_size)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE

	# Collect used cells to define the region
	var used: Array[Vector2i] = []
	for c in floor.get_used_cells(): used.append(c)
	for c in walls.get_used_cells(): used.append(c)

	if used.is_empty():
		astar.region = Rect2i(Vector2i.ZERO, Vector2i.ONE)
	else:
		var minp: Vector2i = used[0]
		var maxp: Vector2i = used[0]
		for p in used:
			if p.x < minp.x: minp.x = p.x
			if p.y < minp.y: minp.y = p.y
			if p.x > maxp.x: maxp.x = p.x
			if p.y > maxp.y: maxp.y = p.y
		astar.region = Rect2i(minp, (maxp - minp) + Vector2i.ONE)

	astar.update()

	# Start with everything blocked, then open floors
	astar.fill_solid_region(astar.region, true)
	for c in floor.get_used_cells():
		astar.set_point_solid(c, false)
	for c in walls.get_used_cells():
		astar.set_point_solid(c, true) # (redundant but explicit)

func is_walkable(cell: Vector2i) -> bool:
	return not astar.is_point_solid(cell)

func find_path_cells(start_cell: Vector2i, end_cell: Vector2i):
	if astar.is_point_solid(end_cell):
		return []  # unreachable
	return astar.get_id_path(start_cell, end_cell)  # returns a vector2i path

func world_to_cell(world_pos: Vector2, layer: TileMapLayer) -> Vector2i:
	if layer == null:
		push_error("GridNav.world_to_cell called with a null layer.")
		return Vector2i.ZERO
	return layer.local_to_map(layer.to_local(world_pos))

func cell_to_world_center(cell: Vector2i, layer: TileMapLayer) -> Vector2:
	var local: Vector2 = layer.map_to_local(cell)
	return layer.to_global(local)
