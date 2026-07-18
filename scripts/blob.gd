extends CharacterBody2D

var direction 
var grid_pos
var activated = false
var ray: RayCast2D


@export var speed = 1200.0

func setup(_direction):
	direction = _direction
	#velocity = direction*speed
	activated = false
	ray = $RayCast2D
	ray.target_position = direction * 64
	
func step():
	if ray.is_colliding() and activated:
		direction *= -1
	position += direction * 64
	activated = true 
	
	ray.target_position = direction * 64
	

func _physics_process(delta):
	if Input.is_action_just_pressed("step"):
		step()
	#var collision = move_and_collide(velocity * delta)
	#if collision:
		#var normal = collision.get_normal()
		#if abs(normal.x) > abs(normal.y):
			#velocity.x *= -1
		#else:
			#velocity.y *= -1
		#velocity = _snap_dir(velocity)
		#direction = velocity.normalized()
	pass

func _snap_dir(v: Vector2) -> Vector2:
	var speed = v.length()
	var dir = Vector2(sign(round(v.x / speed)), sign(round(v.y / speed)))
	return dir * speed
	
