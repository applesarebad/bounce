class_name UndoSystem
extends Node

## Turn-granular undo. One entry per shot, not per tick — undoing puts the world
## back to before the ball was fired, however far the cascade ran from there.
##
## Entries use the same record shape as SaveSystem, so one applier restores both:
##   id -> pre-turn state          the object moved or changed
##   id -> {"_gone": true}         the object was created this turn; undo unmakes it
##   id -> pre-turn state+_scene   the object was destroyed; undo rebuilds it
##
## An entry holds only what the turn actually touched, so stack memory scales
## with how long the session has run, not with how big the world is.

@export var save_system: SaveSystem
@export var world: World

## 0 for unlimited. Entries are a handful of small dictionaries each, and a
## puzzle game with no per-island reset wants undo to reach a long way back.
@export var max_depth: int = 0

signal stack_changed()

var _stack: Array[Dictionary] = []
var _open: Dictionary = {}       ## id -> state before this turn first touched it
var _open_world: Dictionary = {}
var _in_turn: bool = false
var _restoring: bool = false


func depth() -> int:
	return _stack.size()


func can_undo() -> bool:
	return not _stack.is_empty()


func is_turn_open() -> bool:
	return _in_turn


# --- Turn lifecycle ---------------------------------------------------------

func begin_turn() -> void:
	if _in_turn or _restoring:
		return
	_in_turn = true
	_open.clear()
	_open_world = world.capture_world_state() if world else {}


func end_turn() -> void:
	if not _in_turn:
		return
	_in_turn = false

	var world_now: Dictionary = world.capture_world_state() if world else {}
	if _open.is_empty() and world_now == _open_world:
		# The ball went out and came back without moving anything. Don't leave a
		# no-op on the stack for the player to press undo through.
		_open_world = {}
		return

	_stack.push_back({"objects": _open.duplicate(true), "world": _open_world})
	_open.clear()
	_open_world = {}

	if max_depth > 0 and _stack.size() > max_depth:
		_stack.pop_front()
	stack_changed.emit()


## Abandon the turn in progress and put back whatever it already touched, without
## consuming a stack entry. Used when undo is pressed mid-flight.
func cancel_turn() -> void:
	if not _in_turn:
		return
	_in_turn = false
	if not _open.is_empty() or not _open_world.is_empty():
		_apply(_open, _open_world)
	_open.clear()
	_open_world = {}


# --- Recording --------------------------------------------------------------
# Objects report themselves. Only the first report per turn matters — that's the
# state undo has to get back to.

## Call BEFORE changing anything. Calling it after captures the new state and
## the change becomes silently un-undoable.
func record(node: Node) -> void:
	if not _in_turn or _restoring:
		return
	var id: String = node.save_id()
	if _open.has(id):
		return
	_open[id] = node.save_state()


func record_created(node: Node) -> void:
	if not _in_turn or _restoring:
		return
	var id: String = node.save_id()
	if _open.has(id):
		return
	_open[id] = {"_gone": true}


## Call before the node leaves the tree. The entry carries the scene to rebuild
## from, so anything destructible has to be its own scene file — a plain child
## node has no scene_file_path and can't be reinstated.
func record_destroyed(node: Node) -> void:
	if not _in_turn or _restoring:
		return
	var id: String = node.save_id()
	if _open.has(id):
		# Already touched this turn. If it was created this turn, undo already
		# unmakes it and must not also try to rebuild it.
		if not _open[id].get("_gone", false):
			_open[id]["_scene"] = node.scene_file_path
		return
	var state: Dictionary = node.save_state()
	state["_scene"] = node.scene_file_path
	_open[id] = state


# --- Undo -------------------------------------------------------------------

func undo() -> bool:
	if _in_turn or _stack.is_empty():
		return false
	var entry: Dictionary = _stack.pop_back()
	_apply(entry.get("objects", {}), entry.get("world", {}))
	stack_changed.emit()
	return true


func clear() -> void:
	_stack.clear()
	stack_changed.emit()


func _apply(objects: Dictionary, world_state: Dictionary) -> void:
	_restoring = true
	if save_system:
		save_system.apply_objects(objects)
	if world and not world_state.is_empty():
		world.restore_world_state(world_state)
	_restoring = false


# --- Persistence ------------------------------------------------------------
# The stack rides along in the save file. That's what makes undo a real answer
# to an unwinnable world: a player who pushes a log into the ocean can still back
# out of it after quitting and coming back.

func serialize() -> Array:
	return _stack.duplicate(true)


func deserialize(data: Array) -> void:
	_stack.clear()
	for e in data:
		if typeof(e) == TYPE_DICTIONARY:
			_stack.push_back(e)
	stack_changed.emit()
