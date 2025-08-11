extends RefCounted
class_name Job

enum Status { OPEN, RESERVED, ACTIVE, DONE, CANCELLED }

var data: Dictionary = {}	# e.g. {"room_kind":"treasury"}

var id: int
var type: String
var target_cell: Vector2i
var status: int = Status.OPEN
var reserved_by: NodePath = NodePath("")
var created_at_ms: int = Time.get_ticks_msec()

func is_open() -> bool: return status == Status.OPEN
