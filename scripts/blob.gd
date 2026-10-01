extends Node2D

var direction: Vector2
var grid_pos: Vector2
var distance: int = 0
var timedout: bool = false
var ray: RayCast2D

@export var speed: float = 1000



var loop_history: Array = []
var loop_seen: Dictionary = {}
@export var loop_tracking_distance: int = 0
const DIRS := [Vector2(0,-1), Vector2(1,0), Vector2(0,1), Vector2(-1,0)]

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
	
	var entry_cell := Vector2i(floor(position / Constants.GRID_SIZE))
	var entry_dir := direction
	var loop_hits := []
	var reset_tracker = false
	
	var tween = create_tween()
	ray.position = direction * Constants.GRID_SIZE/4
	ray.target_position = direction * Constants.GRID_SIZE*3/4
	ray.force_raycast_update()

	if ray.is_colliding():
		collider = ray.get_collider()

		if collider is Portal:
			portal = collider
			var out_dir = portal.output_direction(direction)
			var blocked = portal.outside(direction)
			var flat_box = blocked != null and blocked is Box and not blocked.hits_diagonal(out_dir)

			if flat_box:
				blocked.hit(direction)
				loop_hits.append(blocked)
				bounced_at_portal = true
				direction *= Transform2D() * -1
				target = direction*Constants.GRID_SIZE
				bounce_anim = true
			else:
				portaling = true
				loop_hits.append(portal)
				old_target = (Constants.GRID_SIZE/2)*direction
				direction = portal.output_direction(direction)
				collider = blocked
		
		if not bounced_at_portal:
			if collider == null:
				target = direction * ((Constants.GRID_SIZE/2) if portaling else Constants.GRID_SIZE)
			elif collider.is_in_group("player"):
				timedout = true
				target = direction * ((Constants.GRID_SIZE/2) if portaling else Constants.GRID_SIZE)
			elif collider is Wall:
				var wall = collider
				var transformer = wall.get_reflection(direction)
				if transformer != Transform2D():
					loop_hits.append(wall)
				if transformer == Transform2D() * -1:
					bounce_anim = true
				else:
					target = direction * ((Constants.GRID_SIZE/2) if portaling else Constants.GRID_SIZE)
				direction *= transformer
				if wall.type == 1: reset_tracker = true
				wall.hit(direction)
				if wall.type == 2:
					timedout = true
	else:
		target = direction * Constants.GRID_SIZE

	distance += 1
	snap_pos_to_grid(position)
	if reset_tracker:
		reset_loop_tracking()
	if check_loop(entry_cell, entry_dir, loop_hits):
		detonate()
		return
		
	if reset_tracker:
		reset_loop_tracking()
	
	if bounce_anim:
		tween.tween_property(
			self,
			"position",
			position - (Constants.GRID_SIZE/2) * direction,
			(Constants.GRID_SIZE/2) / speed
		)
		tween.tween_property(
			self,
			"position",
			position,
			(Constants.GRID_SIZE/2) / speed
		)
		await tween.finished

	elif portaling:
		print(target)

		# Move into the portal
		tween.tween_property(
			self,
			"position",
			position + old_target,
			(Constants.GRID_SIZE/2) / speed
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
			(Constants.GRID_SIZE/2) / speed
		)
		await tween.finished

	else:
		tween.tween_property(
			self,
			"position",
			position + target,
			Constants.GRID_SIZE / speed
		)
		await tween.finished


	if not timedout:
		step()
	else:
		detonate.bind(collider).call()

	$RichTextLabel.text = str(distance)

	
func reset_loop_tracking():
	loop_history.clear()
	loop_seen.clear()

func state_key(cell: Vector2i, dir: Vector2) -> Vector3i:
	return Vector3i(cell.x, cell.y, DIRS.find(dir))

const REQUIRED_PASSES := 5

func check_loop(entry_cell: Vector2i, entry_dir: Vector2, hits: Array) -> bool:
	if distance < loop_tracking_distance:
		return false
	var key = state_key(entry_cell, entry_dir)

	if loop_seen.has(key):
		var record = loop_seen[key]
		record.count += 1

		if record.count >= REQUIRED_PASSES:
			var lap = loop_history.slice(record.index)
			var to_break := {}
			for entry in lap:
				for obj in entry.hits:
					if obj != null and is_instance_valid(obj):
						to_break[obj] = true
			for obj in to_break.keys():
				if obj.has_method("force_break"):
					obj.force_break()
			return true

		record.index = loop_history.size()
		loop_seen[key] = record
		loop_history.append({hits = hits})
		return false

	loop_seen[key] = {index = loop_history.size(), count = 1}
	loop_history.append({hits = hits})
	return false


func detonate(collider = null):
	# The projectile's journey is over either way — hand the camera back to the
	# player now, whether or not this hit was the player. If it was, the player's
	# own move()/fling() (triggered below) is what the camera will then track,
	# live, through world._process(); if it wasn't, there's simply nothing left
	# to point the camera at except the player.
	if World.instance:
		World.instance.release()
	if collider and collider.has_method("_on_body_entered"):
		collider._on_body_entered(direction, distance)
	queue_free()

func is_active():
	return distance > 0

func _physics_process(delta):
	pass
	
func snap_pos_to_grid(pos: Vector2, grid_size: float = Constants.GRID_SIZE) -> Vector2:
	return pos.snapped(Vector2(grid_size, grid_size))
