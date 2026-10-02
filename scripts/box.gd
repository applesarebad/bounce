extends Wall
class_name Box

enum Corner { BOX, TOP_LEFT, TOP_RIGHT, BOTTOM_LEFT, BOTTOM_RIGHT }

@export var corner = Corner.BOX

const CORNER_SIGN := {
	Corner.TOP_LEFT:     Vector2(1, 1),
	Corner.TOP_RIGHT:    Vector2(-1, 1),
	Corner.BOTTOM_LEFT:  Vector2(1, -1),
	Corner.BOTTOM_RIGHT: Vector2(-1, -1),
}

# Full-cell mirror/bounce transforms. Only the branch chosen by hits_diagonal()
# is ever the physically correct one for a given corner — the other two are
# meaningless for that corner and never applied.
const MIRROR_SLASH := Transform2D(Vector2(0, -1), Vector2(-1, 0), Vector2.ZERO)  # "/"
const MIRROR_BACK  := Transform2D(Vector2(0, 1), Vector2(1, 0), Vector2.ZERO)    # "\"
const BOUNCE_BACK  := Transform2D(Vector2(-1, 0), Vector2(0, -1), Vector2.ZERO)  # straight reversal


func get_reflection(dir = Vector2()) -> Transform2D:
	if corner == Corner.BOX or not hits_diagonal(dir):
		return BOUNCE_BACK
	var s: Vector2 = CORNER_SIGN[corner]
	return MIRROR_SLASH if s.x * s.y > 0 else MIRROR_BACK


func hits_diagonal(direction: Vector2) -> bool:
	if corner == Corner.BOX:
		return false
	var s: Vector2 = CORNER_SIGN[corner]
	return direction == Vector2(s.x, 0) or direction == Vector2(0, s.y)


func reflect(direction: Vector2) -> Vector2:
	var v := get_reflection(direction) * Vector2(direction)
	return Vector2(roundi(v.x), roundi(v.y))


func hit(dir):
	var ray = RayCast2D.new()
	ray.hit_from_inside = true
	ray.collide_with_areas = true
	ray.position = dir * Constants.GRID_SIZE/4
	ray.target_position = dir * Constants.GRID_SIZE*3/4
	add_child(ray)
	ray.force_raycast_update()
	if ray.is_colliding() and ray.get_collider() is Wall:
		ray.get_collider().hit(dir)
	ray.queue_free()


func soft(dir: Vector2) -> bool:
	var ray = RayCast2D.new()
	ray.hit_from_inside = true
	ray.collide_with_areas = true
	ray.position = dir * Constants.GRID_SIZE/4
	ray.target_position = dir * Constants.GRID_SIZE*3/4
	add_child(ray)
	ray.force_raycast_update()
	var collider = null
	if ray.is_colliding():
		collider = ray.get_collider()
	ray.queue_free()

	if collider is Portal:
		var out_dir = collider.output_direction(dir)
		var block = collider.outside(dir)
		if block is Wall and block.get_reflection(out_dir) != Transform2D() and !block.soft(out_dir):
			return false
		return true
	elif collider is Wall:
		return not (collider.get_reflection(dir) != Transform2D() and !collider.soft(dir))
	return true


func move(dir, speed):
	var ray = RayCast2D.new()
	ray.hit_from_inside = true
	ray.collide_with_areas = true
	ray.position = dir * Constants.GRID_SIZE/4
	ray.target_position = dir * Constants.GRID_SIZE*3/4
	add_child(ray)
	ray.force_raycast_update()
	var collider = null
	if ray.is_colliding():
		collider = ray.get_collider()
	ray.queue_free()

	if collider is Portal:
		var out_dir = collider.output_direction(dir)
		var block = collider.outside(dir)
		if block is Box:
			block.move(out_dir, speed)
		elif block is Wall:
			block.hit(out_dir)

		var tween = create_tween()
		tween.tween_property(self, "position", position + (Constants.GRID_SIZE/2)*dir, (Constants.GRID_SIZE/2)/speed)
		await tween.finished
		collider.teleport(self, dir)
		tween = create_tween()
		tween.tween_property(self, "position", position + (Constants.GRID_SIZE/2)*out_dir, (Constants.GRID_SIZE/2)/speed)
		await tween.finished
	else:
		if collider is Box:
			collider.move(dir, speed)
		elif collider is Wall:
			collider.hit(dir)
		var tween = create_tween()
		tween.tween_property(self, "position", position + Constants.GRID_SIZE*dir, Constants.GRID_SIZE/speed)
		await tween.finished
	print("box: " + str(is_on_ground()))


func is_on_ground() -> bool:
	var cell := Vector2i((global_position / Constants.GRID_SIZE).floor())
	return Groundcheck.ground.get_cell_source_id(cell) != -1
