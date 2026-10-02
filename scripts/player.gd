extends Area2D

const blob = preload("res://scenes/blob.tscn")
var moving = false
@export var speed = 500

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
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
	get_parent().add_child(b)
	# Hand the camera to the projectile before it takes its first step, so it's
	# already the thing being framed/followed from frame one rather than
	# cutting over mid-flight.
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
	if distance < 10:
		move(dir)
	else:
		fling(dir)

func move(dir):
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
			await tween.finished

			collider.teleport(self, dir)

			tween = create_tween()
			tween.tween_property(self, "position", position + (Constants.GRID_SIZE/2)*out_dir, (Constants.GRID_SIZE/2)/speed)
			await tween.finished
			moving = false	
	else:
		if $ray.is_colliding() and $ray.get_collider() is Box:
			$ray.get_collider().move(dir, speed)
		moving = true
		var tween = create_tween()
		tween.tween_property(self, "position", position + Constants.GRID_SIZE*dir, Constants.GRID_SIZE / speed)
		tween.tween_callback(func(): 
			moving = false
			)
		await tween.finished
	snap_pos_to_grid(position)
	print(is_on_ground())
	# The player has actually stopped here — every branch above falls through
	# to this point, awaits included — so this is the one correct place to
	# re-check which region the player is standing in.
	if World.instance:
		World.instance.on_player_settled()
	
	
func fling(dir):
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
				await tween.finished

				collider.teleport(self, dir)
				dir = out_dir

				tween = create_tween()
				tween.tween_property(self, "position", position + (Constants.GRID_SIZE/2)*dir, (Constants.GRID_SIZE/4)/speed)
				await tween.finished
		else:
			if $ray.is_colliding() and $ray.get_collider() is Box:
				$ray.get_collider().move(dir, 2*speed)
			var tween = create_tween()
			tween.tween_property(self, "position", position + Constants.GRID_SIZE*dir, (Constants.GRID_SIZE/2)/speed)
			await tween.finished
	snap_pos_to_grid(position)
	print(is_on_ground())
	# Loop only exits via the break statements above, so this runs exactly once,
	# after the fling has genuinely come to rest.
	if World.instance:
		World.instance.on_player_settled()
			
func snap_pos_to_grid(pos: Vector2, grid_size: float = Constants.GRID_SIZE) -> Vector2:
	return pos.snapped(Vector2(grid_size, grid_size))

func is_on_ground() -> bool:
	var cell := Vector2i((global_position / Constants.GRID_SIZE).floor())
	return Groundcheck.ground.get_cell_source_id(cell) != -1
