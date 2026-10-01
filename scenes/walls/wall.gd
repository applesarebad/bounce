extends Area2D
class_name Wall

@export var type = 0
#0 normal
#1 breakeable
#2 lasers
#3 seethrough
#4 oneway
@export var diagonal = false
@export var reflection: Transform2D = Transform2D()

## Discriminates walls sharing a cell — a north wall and a west wall painted on
## the same cell both sit at that coordinate. Set by ObjectBaker's default_kind
## per layer; override per-instance only if hand-placing.
@export var kind: StringName = &"wall"

var _id: String = ""


func _ready():
	if Engine.is_editor_hint():
		return
	if _id.is_empty():
		_id = SaveableObject.make_id(global_position, kind)
	add_to_group(SaveSystem.GROUP)
	# No-op unless a turn is open, so walls present at level load don't register
	# as having been "created" this turn.
	if SaveableObject.undo:
		SaveableObject.undo.record_created(self)


func _process(delta):
	pass


func get_reflection(dir = Vector2(0,0)):
	if type < 4:
		return reflection
	if type == 4:
		if dir == reflection.x:
			return Transform2D()
		else:
			return Transform2D() * -1


func hit(dir):
	if type == 1:
		_destroy()


func soft(dir):
	return false


func force_break():
	_destroy()


# --- Saving -------------------------------------------------------------

func save_id() -> String:
	return _id


func set_save_id(id: String) -> void:
	_id = id


## No mutable fields of its own — a plain Wall never changes once placed.
## Box overrides this to add cell position.
func save_state() -> Dictionary:
	return {}


func load_state(state: Dictionary) -> void:
	pass


## Call before changing any state that should be undoable. Not needed for plain
## Wall today (nothing mutates it besides destruction), but here so a future
## field on Wall itself — or a Wall subclass other than Box — has it available.
func mutate() -> void:
	if SaveableObject.undo:
		SaveableObject.undo.record(self)


func _destroy() -> void:
	if SaveableObject.undo:
		SaveableObject.undo.record_destroyed(self)
	remove_from_group(SaveSystem.GROUP)
	queue_free()
