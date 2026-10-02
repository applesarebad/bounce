extends Area2D
class_name Wall

@export var type = 0
#0 normal
#1 breakeable
#2 lasers
#3 seethrough
#4 oneway
@export var diagonal = false
@export var reflection: Transform2D = Transform2D()

func _ready():
	pass


func _process(delta):
	pass


func get_reflection(dir = Vector2(0,0)):
	if type < 4:
		return reflection
	if type == 4:
		if dir == reflection.x:
			return Transform2D()
		else:
			return Transform2D() * -1


func hit(dir):
	if type == 1:
		queue_free()


func soft(dir):
	return false


func force_break():
	queue_free()
