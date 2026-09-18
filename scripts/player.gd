extends Area2D

const blob = preload("res://scenes/blob.tscn")
var moving = false
@export var speed = 320

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
	#and !$ray.get_collider().diagonal :
		transformer = collider.get_reflection(dir)
		#if collider.type == 4:
			#if dir != collider.reflection.x:
				#move(dir*-1)
				#return 
		#elif collider.type != 2:
			 
	if transformer != null and (transformer == Transform2D() * -1):
		move(dir*-1)
		return
	var b = blob.instantiate()
	get_parent().add_child(b)
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
	var target = 64*dir
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
	print("colliding: ", $ray.is_colliding(), " collider: ", $ray.get_collider())
	if $ray.is_colliding() and $ray.get_collider() is Wall and $ray.get_collider().get_reflection(dir) != Transform2D() and !$ray.get_collider().soft(dir):
		$ray.get_collider().hit()
	else:
		if $ray.is_colliding() and $ray.get_collider() is Box:
			$ray.get_collider().move(dir, speed)
		moving = true
		var tween = create_tween()
		tween.tween_property(self, "position", position + 64*dir, 64.0 / speed)
		tween.tween_callback(func(): 
			moving = false
			)
	snap_pos_to_grid(position)
	
	
func fling(dir):
	while true:
		moving = true
		var target = aim(dir)
		if $ray.is_colliding() and $ray.get_collider() is Wall and $ray.get_collider().get_reflection(dir) != Transform2D() and !$ray.get_collider().soft(dir):
			$ray.get_collider().hit()
			moving = false
			break
		else:
			if $ray.is_colliding() and $ray.get_collider() is Box:
				$ray.get_collider().move(dir, 2*speed)
			var tween = create_tween()
			tween.tween_property(self, "position", position + 64*dir, 32.0 / speed)
			await tween.finished
	snap_pos_to_grid(position)
			
func snap_pos_to_grid(pos: Vector2, grid_size: float = 64.0) -> Vector2:
	return pos.snapped(Vector2(grid_size, grid_size))
func is_on_ground() -> bool:
	var cell := Vector2i((global_position / 64.0).floor())
	return Groundcheck.ground.get_cell_source_id(cell) != -1
	
