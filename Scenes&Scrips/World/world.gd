# res://Scripts/World.gd
extends Node2D

@onready var floor: TileMapLayer = $Tilemaps/Floor
@onready var walls: TileMapLayer = $Tilemaps/Walls
@onready var click: ClickInput = $ClickInput
@onready var goblin: Goblin = $Goblin

@onready var rooms: TileMapLayer = $Tilemaps/Rooms

func _ready() -> void:
	
	# add JobOverlay if not present
	if get_node_or_null("JobOverlay") == null:
		var o: JobOverlay = JobOverlay.new()
		o.name = "JobOverlay"
		add_child(o)
		if o.floor_layer_path == NodePath(""):
			o.floor_layer_path = floor.get_path()

	# Groups for auto-wiring (safe to call every run)
	if not floor.is_in_group("floor_layer"):
		floor.add_to_group("floor_layer")
	if not walls.is_in_group("wall_layer"):
		walls.add_to_group("wall_layer")

	# Build nav + init jobs
	if not rooms.is_in_group("room_layer"):
		rooms.add_to_group("room_layer")

	GridNav.build_from_layers(floor, walls)
	
	JobManager.treasury_capacity_per_tile = 5	# or 10, etc.
	JobManager.init(floor, walls, rooms)
	

	# Optional: set the Treasury tile once (hardcoded)
	 #JobManager.room_treasury_source_id = <src_id>
	 #JobManager.room_treasury_atlas_coords = Vector2i(<x>, <y>)
	 #JobManager.room_treasury_alt = 0


	# (Optional) Point ClickInput to layers if you prefer explicit paths
	if click.floor_layer_path == NodePath(""):
		click.floor_layer_path = floor.get_path()
	if click.walls_layer_path == NodePath(""):
		click.walls_layer_path = walls.get_path()

	# (Optional) Let Goblin auto-wire its agents to this floor
	if goblin.floor_layer_path == NodePath(""):
		goblin.floor_layer_path = floor.get_path()
