extends Node

func is_ground(world_pos: Vector2) -> bool:
	for layer in get_tree().get_nodes_in_group("ground"):
		var cell = layer.local_to_map(layer.to_local(world_pos))
		if layer.get_cell_source_id(cell) != -1:
			return true
	return false
