extends Area2D
class_name Wall

@export var type = 0
#0 normal
#1 breakeable
#2 lasers
#3 seethrough
#4 oneway
#5 laserway
@export var diagonal = false
@export var reflection: Transform2D = Transform2D()

func _ready() -> void:

	var anim_name = "default"
	var sprite = $AnimatedSprite2D
	var max_frame = sprite.sprite_frames.get_frame_count(anim_name)
	var random_frame = randi_range(0, max_frame - 1)
	sprite.frame = random_frame

func _process(delta):
	pass


func get_reflection(dir = Vector2(0,0)):
	if type < 4:
		return reflection
	if type == 4:
		print("reflecting 4")
		if dir == reflection.x or dir == reflection.y:
			print("t 4")
			return Transform2D()
			
		else:
			print("fake 4")
			print(dir, reflection.x, reflection.y)
			return Transform2D() * -1
			


func hit(dir):
	if type == 1:
		destroy()


func soft(dir):
	return false


func force_break():
	
	destroy()
func destroy():
	global_position = Vector2(100000,100000)
