class_name Level
extends Node

const MAX_UNDO := 100

var scenes: Array[Node2D] = []
var undo_stack: Array = []
var initial_positions: Array[Vector2] = []

var success = false


func _ready():
	await get_tree().create_timer(1).timeout
	initialize_level()


func initialize_level():
	setup_scenes()

	initial_positions.clear()

	for scene in scenes:
		initial_positions.append(scene.global_position)

	undo_stack.clear()
	undo_stack.append(initial_positions.duplicate())


func setup_scenes():
	scenes.clear()

	for layer in [$walls/Horizontals, $walls/Verticals, $walls/Diagonals, $Objects]:
		for scene in layer.get_children():
			if scene is Node2D:
				scenes.append(scene)


func save():
	var state: Array[Vector2] = []

	for scene in scenes:
		state.append(scene.global_position)

	undo_stack.append(state)

	if undo_stack.size() > MAX_UNDO:
		undo_stack.pop_front()


func undo():
	print("before undo: " + str(undo_stack.size()))

	if undo_stack.size() < 2:
		return

	# Remove current state
	undo_stack.pop_back()

	# Restore previous state
	var state: Array[Vector2] = undo_stack.back()

	for i in scenes.size():
		if i < state.size():
			scenes[i].global_position = state[i]


func _process(delta):
	pass
