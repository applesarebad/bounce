extends Area2D

const blob = preload("res://scenes/blob.tscn")
var moving = false
@export var speed = 500

var _cancelled := false

func _ready():
	pass

func _process(delta):
	var direction = get_direction()
	if direction != Vector2(0,0):
		shoot(direction)

func shoot(dir):
	if moving:
		return
	var target = aim(dir)
	var collider = null
	var transformer = null
	if $ray.is_colliding():
		collider = $ray.get_collider()
	if collider != null and collider is Wall:
		transformer = collider.get_reflection(dir)
		if collider.type == 2:
			return
		if collider.type == 3:
			transformer = Transform2D()
	if collider is Portal and collider.outside(dir) is Wall:
		print("blocked")
		transformer = collider.outside(dir).get_reflection(collider.output_direction(dir))
	if transformer != null and (transformer == Transform2D() * -1):
		move(dir*-1)
		return
	var b = blob.instantiate()
	if get_parent().has_node("Blobs"):
		get_parent().get_node("Blobs").add_child(b)
	else:
		get_parent().add_child(b)
	b.global_position = global_position  
	if World.instance:
		World.instance.track(b)
	b.setup(dir, global_position)

func get_direction() -> Vector2:
	if Input.is_action_just_pressed("ui_left"):
		return Vector2(-1, 0)
	if Input.is_action_just_pressed("ui_right"):
		return Vector2(1, 0)
	if Input.is_action_just_pressed("ui_up"):
		return Vector2(0, -1)
	if Input.is_action_just_pressed("ui_down"):
		return Vector2(0, 1)
	return Vector2.ZERO

func aim(dir):
	var target = Constants.GRID_SIZE*dir
	$ray.target_position = target
	$ray.force_raycast_update()
	return target

func _on_body_entered(dir, distance):
	print(dir)
	if distance < 20:
		move(dir)
	else:
		fling(dir)

# stops whatever move()/fling() is mid-flight. kill()ing a tween alone won't
# wake up an `await tween.finished` sitting on it, so wait_tween() below polls
# this flag instead and bails itself. call this, then apply your undo snapshot.
func stop_movement() -> void:
	_cancelled = true
	moving = false

# swap-in for `await tween.finished` everywhere below. returns early (and kills
# the tween) if stop_movement() fires while we're waiting.
func wait_tween(tween: Tween) -> void:
	while tween.is_valid() and tween.is_running() and not _cancelled:
		await get_tree().process_frame
	if _cancelled and tween.is_valid():
		tween.kill()

func move(dir):
	_cancelled = false
	var target = aim(dir)
	var collider = null
	print("colliding: ", $ray.is_colliding(), " collider: ", $ray.get_collider())
	if $ray.is_colliding():
		collider = $ray.get_collider()
	if collider is Wall and collider.get_reflection(dir) != Transform2D() and !collider.soft(dir):
		$ray.get_collider().hit(dir)
	elif collider is Portal:
		var out_dir = collider.output_direction(dir)
		var block = collider.outside(dir)
		if block is Wall and block.get_reflection(out_dir) != Transform2D() and !block.soft(out_dir):
			block.hit(out_dir)
		else:
			if block is Box:
				block.move(out_dir, speed)
			moving = true
			var tween = create_tween()
			tween.tween_property(self, "position", position + (Constants.GRID_SIZE/2)*dir, (Constants.GRID_SIZE/2)/speed)
			await wait_tween(tween)
			if _cancelled:
				return
			collider.teleport(self, dir)
			tween = create_tween()
			tween.tween_property(self, "position", position + (Constants.GRID_SIZE/2)*out_dir, (Constants.GRID_SIZE/2)/speed)
			await wait_tween(tween)
			moving = false
			if _cancelled:
				return
	else:
		if $ray.is_colliding() and $ray.get_collider() is Box:
			$ray.get_collider().move(dir, speed)
		moving = true
		var tween = create_tween()
		tween.tween_property(self, "position", position + Constants.GRID_SIZE*dir, Constants.GRID_SIZE / speed)
		tween.tween_callback(func():
			moving = false
			)
		await wait_tween(tween)
		if _cancelled:
			return
	snap_pos_to_grid(position)
	print(is_on_ground())
	get_parent().save()
	if World.instance:
		World.instance.on_player_settled()

func fling(dir):
	_cancelled = false
	while true:
		moving = true
		var target = aim(dir)
		var collider = null
		if $ray.is_colliding():
			collider = $ray.get_collider()
		if collider is Wall and collider.get_reflection(dir) != Transform2D() and !collider.soft(dir):
			collider.hit(dir)
			moving = false
			break
		elif collider is Portal:
			var out_dir = collider.output_direction(dir)
			var block = collider.outside(dir)
			if block is Wall and block.get_reflection(out_dir) != Transform2D() and !block.soft(out_dir):
				block.hit(out_dir)
				moving = false
				break
			else:
				if block is Box:
					block.move(out_dir, 2*speed)
				var tween = create_tween()
				tween.tween_property(self, "position", position + (Constants.GRID_SIZE/2)*dir, (Constants.GRID_SIZE/4)/speed)
				await wait_tween(tween)
				if _cancelled:
					return
				collider.teleport(self, dir)
				dir = out_dir
				tween = create_tween()
				tween.tween_property(self, "position", position + (Constants.GRID_SIZE/2)*dir, (Constants.GRID_SIZE/4)/speed)
				await wait_tween(tween)
				if _cancelled:
					return
		else:
			if $ray.is_colliding() and $ray.get_collider() is Box:
				$ray.get_collider().move(dir, 2*speed)
			var tween = create_tween()
			tween.tween_property(self, "position", position + Constants.GRID_SIZE*dir, (Constants.GRID_SIZE/2)/speed)
			await wait_tween(tween)
			if _cancelled:
				return
	snap_pos_to_grid(position)
	print(is_on_ground())
	get_parent().save()
	if World.instance:
		World.instance.on_player_settled()

func snap_pos_to_grid(pos: Vector2, grid_size: float = Constants.GRID_SIZE) -> Vector2:
	return pos.snapped(Vector2(grid_size, grid_size))

func is_on_ground() -> bool:
	var cell := Vector2i((global_position / Constants.GRID_SIZE).floor())
	return Groundcheck.ground.get_cell_source_id(cell) != -1
