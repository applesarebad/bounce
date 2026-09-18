
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

func soft(dir: Vector2) -> bool:
	var ray = RayCast2D.new()
	ray.hit_from_inside = true
	ray.collide_with_areas = true
	ray.position = dir * 16
	ray.target_position = dir * 48
	add_child(ray)         
	ray.force_raycast_update()
	var blocked = ray.is_colliding() and ray.get_collider() is Wall and ray.get_collider().get_reflection(dir) != Transform2D() and !ray.get_collider().soft(dir)
	ray.queue_free()
	return not blocked
func move(dir, speed):
	var ray = RayCast2D.new()
	ray.hit_from_inside = true
	ray.collide_with_areas = true
	ray.position = dir * 16
	ray.target_position = dir * 48
	add_child(ray)         
	ray.force_raycast_update()
	if ray.is_colliding() and ray.get_collider() is Box:
		ray.get_collider().move(dir,speed)
	elif ray.is_colliding() and ray.get_collider() is Wall:
		ray.get_collider().hit()
	ray.queue_free()
	var tween = create_tween()   
	tween.tween_property(self, "position", position + 64*dir, 64.0 / speed)
	
