@tool
class_name SaveableObject
extends Node2D

## Base for anything that moves, breaks, or gets created during play: crates,
## logs, breakable walls. Anything that can't inherit from this — the blob is an
## Area2D — still takes part by joining the "saveable" group and implementing the
## same methods, and by calling SaveableObject.undo.record(self) before it changes.
##
## Subclasses that add state extend rather than replace, and must call mutate()
## BEFORE touching that state:
##
##   func save_state() -> Dictionary:
##       var d := super()
##       d["charges"] = charges
##       return d
##
##   func load_state(state: Dictionary) -> void:
##       super(state)
##       charges = state.get("charges", charges)
##
##   func spend_charge() -> void:
##       mutate()          # <- before, not after
##       charges -= 1
##
## Ordering is the one place this system can be silently wrong: mutate() captures
## whatever the state is at the moment it's called, so calling it after the change
## records the new value and the change quietly stops being undoable. Position and
## destruction are handled here so the base cases can't get it wrong; added state
## is on you.

const CELL_SIZE := CameraRegion.CELL_SIZE

## Set by World at startup so objects can report changes without a global lookup.
static var undo: UndoSystem

## Discriminates objects sharing a cell — a crate and the wall on that cell's
## north edge sit at the same coordinate.
@export var kind: StringName = &"object"

var _id: String = ""


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if _id.is_empty():
		_id = make_id(global_position, kind)
	add_to_group(SaveSystem.GROUP)
	# No-op unless a turn is open, so authored objects appearing at level load
	# and objects rebuilt by an undo don't register as creations.
	if undo:
		undo.record_created(self)


## Identity comes from the cell the object was authored on. Node paths break the
## first time you rename or reorder something in the editor; an authored cell is
## stable, unique — nothing else starts there — and readable in the save file.
static func make_id(pos: Vector2, k: StringName) -> String:
	var cell := Vector2i((pos / CELL_SIZE).floor())
	return "%d,%d:%s" % [cell.x, cell.y, k]


func save_id() -> String:
	return _id


## Called on objects rebuilt from a record, before load_state. Without it a
## rebuilt object would derive a fresh id from wherever the scene places it and
## drift away from its own history.
func set_save_id(id: String) -> void:
	_id = id


func save_state() -> Dictionary:
	return {"cell": current_cell()}


func load_state(state: Dictionary) -> void:
	if state.has("cell"):
		_move_to(state["cell"])


# --- Mutation ---------------------------------------------------------------

## Report the current state to the open turn before changing it.
func mutate() -> void:
	if undo:
		undo.record(self)


func set_cell(cell: Vector2i) -> void:
	mutate()
	_move_to(cell)


## Use instead of queue_free(). Leaves the group immediately so a second undo in
## the same frame doesn't still see this node, since queue_free defers to the end
## of the frame.
func destroy() -> void:
	if undo:
		undo.record_destroyed(self)
	remove_from_group(SaveSystem.GROUP)
	queue_free()


func current_cell() -> Vector2i:
	return Vector2i((global_position / CELL_SIZE).floor())


func _move_to(cell: Vector2i) -> void:
	global_position = (Vector2(cell) + Vector2(0.5, 0.5)) * CELL_SIZE
