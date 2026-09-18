extends Node2D

var direction: Vector2
var grid_pos: Vector2
var distance: int = 0
var timedout: bool = false
var ray: RayCast2D

@export var speed: float = 100

func setup(_direction, _position):
	direction = _direction
	position = _position
	distance = 0
	ray = $RayCast2D
	step()

func step():
	var target = Vector2.ZERO
	var collider = null
	var portaling = false
	var bounced_at_portal = false
	var portal: Portal
	var old_target = Vector2.ZERO
	
	var bounce_anim = false
	var portal_anim = false
	var tween = create_tween()
	ray.position = direction * 16
	ray.target_position = direction * 48
	ray.force_raycast_update()

	if ray.is_colliding():
		collider = ray.get_collider()

		if collider is Portal:
			portal = collider
			var out_dir = portal.output_direction(direction)
			var blocked = portal.outside(direction)
			var flat_box = blocked != null and blocked is Box and not blocked.hits_diagonal(out_dir)

			if flat_box:
				bounced_at_portal = true
				direction *= Transform2D() * -1
				await get_tree().create_timer(64.0 / speed).timeout
			else:
				portaling = true
				old_target = 32*direction
				direction = portal.output_direction(direction)
				collider = blocked
		
		if not bounced_at_portal:
			if collider == null:
				target = direction * (32 if portaling else 64)
			elif collider.is_in_group("player"):
				timedout = true
				target = direction * (32 if portaling else 64)
			elif collider is Wall:
				var wall = collider
				var transformer = wall.get_reflection(direction)
				if transformer == Transform2D() * -1:
					#await get_tree().create_timer(64.0 / speed).timeout
					bounce_anim = true
				else:
					target = direction * (32 if portaling else 64)
				direction *= transformer
				wall.hit()
				if wall.type == 2:
					timedout = true
	else:
		target = direction * 64

	distance += 1
	snap_pos_to_grid(position)
	
	
	if bounce_anim:
		tween.tween_property(
			self,
			"position",
			position - 32 * direction,
			32.0 / speed
		)
		tween.tween_property(
			self,
			"position",
			position,
			32.0 / speed
		)
		await tween.finished

	elif portaling:
		print(target)

		# Move into the portal
		tween.tween_property(
			self,
			"position",
			position + old_target,
			32.0 / speed
		)
		await tween.finished

		# Teleport
		print(position)
		portal.teleport(self, direction)
		print(position)

		# Move out of the portal
		tween = create_tween()
		tween.tween_property(
			self,
			"position",
			position + target,
			32.0 / speed
		)
		await tween.finished

	else:
		tween.tween_property(
			self,
			"position",
			position + target,
			64.0 / speed
		)
		await tween.finished


	if not timedout:
		step()
	else:
		detonate.bind(collider).call()

	$RichTextLabel.text = str(distance)

	

func detonate(collider = null):
	if collider and collider.has_method("_on_body_entered"):
		collider._on_body_entered(direction, distance)
	queue_free()

func is_active():
	return distance > 0

func _physics_process(delta):
	pass
	
func snap_pos_to_grid(pos: Vector2, grid_size: float = 64.0) -> Vector2:
	return pos.snapped(Vector2(grid_size, grid_size))
