# res://Scripts/Goblin.gd
extends CharacterBody2D
class_name Goblin

@export var agent_path: NodePath
@export var floor_layer_path: NodePath

@onready var agent: MovementAgent = null
@onready var worker: WorkerAgent = null

func _ready() -> void:
	_ensure_agents()

func _ensure_agents() -> void:
	var mov: MovementAgent = null
	if agent_path != NodePath(""):
		mov = get_node_or_null(agent_path) as MovementAgent
	if mov == null:
		mov = get_node_or_null("MovementAgent") as MovementAgent
	if mov == null:
		mov = MovementAgent.new()
		mov.name = "MovementAgent"
		add_child(mov)

	var work: WorkerAgent = get_node_or_null("WorkerAgent") as WorkerAgent
	if work == null:
		work = WorkerAgent.new()
		work.name = "WorkerAgent"
		add_child(work)

	var floor: TileMapLayer = null
	if floor_layer_path != NodePath(""):
		floor = get_node_or_null(floor_layer_path) as TileMapLayer
	if floor == null:
		floor = get_tree().get_first_node_in_group("floor_layer") as TileMapLayer

	if floor != null:
		if mov.tilemap_layer_path == NodePath(""):
			mov.tilemap_layer_path = floor.get_path()
		if work.tilemap_layer_path == NodePath(""):
			work.tilemap_layer_path = floor.get_path()

	agent = mov
	worker = work

func go_to_cell(cell: Vector2i) -> void:
	if agent != null:
		agent.set_destination_cell(cell)
