class_name SaveSystem
extends Node

## Diff-based world save. Records only what differs from the authored level, so
## the file stays small and untouched parts of the world pick up level edits made
## later — which matters while the game is still being built.
##
## Saveable nodes join the "saveable" group and implement:
##
##   save_id() -> String
##       Stable identity. Derive it from the cell the object was authored on,
##       not its node path — see SaveableObject.make_id().
##
##   save_state() -> Dictionary
##       Everything mutable about it. Keep it minimal; it's diffed every save
##       and copied into every undo entry that touches the object.
##
##   load_state(state: Dictionary) -> void
##       Apply it. Called once every node is in the tree.
##
##   set_save_id(id: String) -> void          (optional)
##       Called on objects rebuilt from a record, before load_state, so a
##       rebuilt object gets its recorded identity back rather than deriving a
##       new one from wherever the scene happens to place it.
##
## Objects don't declare whether they were authored or spawned at runtime — that
## is worked out here by snapshotting the group at world load.

const VERSION := 1
const GROUP := &"saveable"

signal saved()
signal loaded()

## Runtime-spawned objects are rebuilt under this node.
@export var spawn_root: Node

var _baseline: Dictionary = {}  ## id -> state as the level authored it


# --- Baseline ---------------------------------------------------------------

## Call once, after the world scene is built and before any save is applied.
## Node _ready() runs children-first, so calling this from World._ready() sees
## every authored object already in the group.
func capture_baseline() -> void:
	_baseline.clear()
	for n in get_tree().get_nodes_in_group(GROUP):
		_baseline[n.save_id()] = n.save_state()


# --- Records ----------------------------------------------------------------

func collect() -> Dictionary:
	var objects := {}
	var seen := {}

	for n in get_tree().get_nodes_in_group(GROUP):
		var id: String = n.save_id()
		var state: Dictionary = n.save_state()
		seen[id] = true

		if not _baseline.has(id):
			# Didn't exist when the level loaded, so the record has to carry what
			# to rebuild it from.
			state["_scene"] = n.scene_file_path
			objects[id] = state
		elif state != _baseline[id]:
			# Dictionary == compares by value in Godot 4. If that ever changed,
			# this would over-report rather than under-report, so no data is lost.
			objects[id] = state

	for id in _baseline:
		if not seen.has(id):
			objects[id] = {"_gone": true}

	return objects


## Applies a set of object records. Shared with UndoSystem — a save and an undo
## entry are the same shape, so there's one applier to keep correct rather than
## two that have to agree.
func apply_objects(objects: Dictionary) -> void:
	var present := {}
	for n in get_tree().get_nodes_in_group(GROUP):
		present[n.save_id()] = n

	for id in objects:
		var state: Dictionary = objects[id]

		if state.get("_gone", false):
			if present.has(id):
				# Leave the group before queue_free, which doesn't take effect
				# until end of frame. Otherwise two undos in one frame would both
				# see this node still present.
				present[id].remove_from_group(GROUP)
				present[id].queue_free()
			continue

		if present.has(id):
			present[id].load_state(state)
			continue

		var scene_path: String = state.get("_scene", "")
		if scene_path.is_empty():
			push_warning("Record references '%s', which isn't in the level and has no scene to rebuild from." % id)
			continue
		if spawn_root == null:
			push_warning("Record wants to rebuild '%s' but no spawn_root is set." % id)
			continue

		var packed := load(scene_path) as PackedScene
		if packed == null:
			push_warning("Record references a missing scene for '%s': %s" % [id, scene_path])
			continue
		var node := packed.instantiate()
		spawn_root.add_child(node)
		if node.has_method("set_save_id"):
			node.set_save_id(id)
		node.load_state(state)


func apply(data: Dictionary) -> void:
	apply_objects(data.get("objects", {}))
	loaded.emit()


# --- File IO ----------------------------------------------------------------

static func slot_path(slot: int) -> String:
	return "user://save_%d.dat" % slot


static func slot_exists(slot: int) -> bool:
	return FileAccess.file_exists(slot_path(slot))


static func delete_slot(slot: int) -> Error:
	return DirAccess.remove_absolute(slot_path(slot))


func write(slot: int, world_data: Dictionary = {}) -> Error:
	var data := {
		"version": VERSION,
		"objects": collect(),
		"world": world_data,
	}

	# Write to a temp file and swap it in, so a crash mid-write can't leave a
	# half-written file where the working save used to be.
	var tmp := slot_path(slot) + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		var open_err := FileAccess.get_open_error()
		push_error("Save failed: %s" % error_string(open_err))
		return open_err

	# Godot's own binary format. Vector2i, Dictionary and Array round-trip intact,
	# which JSON does not — it would turn every grid coordinate into a float pair,
	# and the undo stack is nested dictionaries all the way down.
	f.store_var(data)
	f.close()

	var err := DirAccess.rename_absolute(tmp, slot_path(slot))
	if err != OK:
		push_error("Save failed on swap: %s" % error_string(err))
		return err

	saved.emit()
	return OK


func read(slot: int) -> Dictionary:
	if not slot_exists(slot):
		return {}

	var f := FileAccess.open(slot_path(slot), FileAccess.READ)
	if f == null:
		push_error("Load failed: %s" % error_string(FileAccess.get_open_error()))
		return {}
	# allow_objects stays false — a save file is untrusted input even when it's
	# one the player wrote themselves.
	var data: Variant = f.get_var(false)
	f.close()

	if typeof(data) != TYPE_DICTIONARY:
		push_error("Save file isn't a dictionary. Ignoring it.")
		return {}

	var v: Variant = data.get("version", -1)
	if v != VERSION:
		# No guessing at migrations. While the game is in flux, saying so and
		# starting fresh beats half-loading a file you don't understand.
		push_warning("Save is version %s, expected %d. Ignoring it." % [v, VERSION])
		return {}

	return data


## Approximate, human-readable dump for when a save misbehaves. Not the save
## format — JSON flattens Vector2i and friends into strings.
func dump(slot: int) -> String:
	return JSON.stringify(read(slot), "\t")
