extends Area2D

const blob = preload("res://scenes/blob.tscn")

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	var direction = get_direction()
	if direction != Vector2(0,0):
		shoot(direction)

func shoot(direction):
	var b = blob.instantiate()
	b.setup(direction)
	b.position = global_position
	get_parent().add_child(b)
	
	pass

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





func _on_body_entered(body):
	if body.is_in_group('blob'):
		if body.activated:
			self.position += 64*body.direction
			body.queue_free()
