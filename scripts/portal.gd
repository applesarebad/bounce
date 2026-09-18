extends Area2D
class_name Portal

@export var link:Portal

func get_direction() -> Vector2:
	var d = Vector2.RIGHT.rotated(rotation)
	return Vector2(round(d.x), round(d.y))
	
func output_direction(dir):
	var x = 1
	if dir == get_direction():
		x = -1
	return link.get_direction() * x
func teleport(obj, dir: Vector2):
	obj.global_position = link.global_position
	return output_direction(dir)

func outside(dir):
	var out = output_direction(dir)
	var ray = RayCast2D.new()
	ray.hit_from_inside = true
	ray.collide_with_areas = true
	ray.position = out * 16
	ray.target_position = out * 16
	link.add_child(ray)         
	ray.force_raycast_update()
	var blocked = null
	if ray.is_colliding() and ray.get_collider() is not Portal:
		blocked = ray.get_collider()
	ray.queue_free()
	return blocked
