# res://Scripts/MovementAgent.gd
extends Node
class_name MovementAgent

@export var tilemap_layer_path: NodePath   # set to World/Tilemaps/Floor
@export var tiles_per_second: float = 8.0
@export var snap_to_cell_center := true

var _tilemap: TileMapLayer
var _owner_body: Node2D
var _moving := false

signal arrived

func _ready():
	if tilemap_layer_path != NodePath(""):
		_tilemap = get_node_or_null(tilemap_layer_path) as TileMapLayer
	if _tilemap == null:
		_tilemap = get_tree().get_first_node_in_group("floor_layer") as TileMapLayer
	if _tilemap == null:
		push_error("MovementAgent: TileMapLayer not set. Set tilemap_layer_path or group your Floor layer as 'floor_layer'.")
		return
	_owner_body = get_parent() as Node2D

func set_destination_cell(target_cell: Vector2i) -> void:
	var start_cell: Vector2i = GridNav.world_to_cell(_owner_body.global_position, _tilemap)
	var cells: PackedVector2Array = GridNav.find_path_cells(start_cell, target_cell)
	if cells.is_empty():
		return
	_move_along_cells(cells)

func set_destination_world(world_pos: Vector2) -> void:
	set_destination_cell(GridNav.world_to_cell(world_pos, _tilemap))

func _move_along_cells(cells: PackedVector2Array) -> void:
	if _moving:
		return
	if cells.size() <= 1:
		call_deferred("_emit_arrived_immediate")
		return
	_moving = true
	await _step_path(cells)
	_moving = false
	arrived.emit()

func _emit_arrived_immediate() -> void:
	arrived.emit()

func _step_path(cells: PackedVector2Array) -> void:
	for i in range(1, cells.size()):
		var cell: Vector2i = cells[i]
		var target: Vector2 = GridNav.cell_to_world_center(cell, _tilemap)

		if snap_to_cell_center and i == 1:
			var start_world: Vector2 = GridNav.cell_to_world_center(cells[0], _tilemap)
			_owner_body.global_position = start_world

		var duration: float = 1.0 / tiles_per_second  # constant time per tile
		var tw: Tween = create_tween()
		tw.tween_property(_owner_body, "global_position", target, duration)\
		  .set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		await tw.finished
