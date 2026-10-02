class_name World
extends Node2D

##   World (world.gd)
##   ├── walls
##   ├── Regions     
##   ├── Objects     
##   ├── Player
##   └── WorldCamera  
##
enum ProjectileFraming {
	NEVER,          
	WHEN_OFFSCREEN,
	ALWAYS,         
}

@export var player: Node2D
@export var regions_root: Node
@export var camera: WorldCamera
@export var start_region: CameraRegion
@export var map_padding_cells: float = 2.0

@export_group("Projectile framing")

@export var projectile_framing: ProjectileFraming = ProjectileFraming.WHEN_OFFSCREEN

@export_range(0.0, 0.4) var offscreen_margin: float = 0.1
@export var projectile_transition_time: float = 0.25

static var instance: World

var regions: Array[CameraRegion] = []
var current_region: CameraRegion
var map_open: bool = false

var _subject: Node2D  
var _tracked: Node2D  

signal region_changed(region: CameraRegion)


func _ready() -> void:
	for c in regions_root.get_children():
		if c is CameraRegion:
			regions.append(c)

	_subject = player
	instance = self

	var start: CameraRegion = start_region
	if start == null:
		start = region_at(player.global_position)
	if start:
		if start.mode == CameraRegion.Mode.FRAME:
			start.visited = true
		_enter_region(start, false)


func _exit_tree() -> void:
	
	if instance == self:
		instance = null


# --- Camera subject ---------------------------------------------------------

## Hand the camera to a projectile
func track(node: Node2D) -> void:
	_tracked = node
	_subject = node
	_evaluate_region(true)


## Give the camera back
func release() -> void:
	_tracked = null
	_subject = player
	_evaluate_region(true)


func subject_position() -> Vector2:
	if _subject == null:
		return Vector2.ZERO
	if _subject.has_method("get_camera_target"):
		return _subject.get_camera_target()
	return _subject.global_position


# --- Region tracking --------------------------------------------------------

func _process(_delta: float) -> void:
	if map_open or _subject == null or current_region == null:
		return

	_evaluate_region(false)

	if current_region.mode != CameraRegion.Mode.FOLLOW:
		return

	var here := region_at(subject_position())
	var limits := current_region.get_bounds()
	if here and here != current_region:
		limits = limits.merge(here.get_bounds())
	camera.update_follow(subject_position(), limits)

func _evaluate_region(allow_frame: bool) -> void:
	var here := region_at(subject_position())
	if here == null or here == current_region:
		return

	if here.mode == CameraRegion.Mode.FOLLOW:
		_enter_region(here)
	elif allow_frame:
		_enter_region(here)
	elif _tracked != null and _projectile_may_reframe():
		_enter_region(here, true, projectile_transition_time)


func _projectile_may_reframe() -> bool:
	match projectile_framing:
		ProjectileFraming.ALWAYS:
			return true
		ProjectileFraming.WHEN_OFFSCREEN:
			var view := camera.get_visible_world_rect()
			var inset := Rect2(
				view.position + view.size * offscreen_margin,
				view.size * (1.0 - 2.0 * offscreen_margin)
			)
			return not inset.has_point(subject_position())
		_:
			return false


func on_player_settled() -> void:
	if map_open:
		return

	var here := region_at(player.global_position)

	if here and here.mode == CameraRegion.Mode.FRAME:
		here.visited = true

	if _tracked != null:
		return

	if here == null or here == current_region:
		return
	_enter_region(here)

func region_at(p: Vector2) -> CameraRegion:
	for r in regions:
		if r.contains_point(p):
			return r
	return null


func _enter_region(r: CameraRegion, animated: bool = true, duration: float = -1.0) -> void:
	current_region = r
	if r.mode == CameraRegion.Mode.FRAME:
		camera.frame_rect(r.get_frame_rect(), animated, duration)
	else:
		camera.begin_follow(r.get_view_height(), animated)
	region_changed.emit(r)


# --- Map mode ---------------------------------------------------------------

func world_rect() -> Rect2:
	var out := Rect2()
	var first := true
	for r in regions:
		if first:
			out = r.get_bounds()
			first = false
		else:
			out = out.merge(r.get_bounds())
	return out.grow(map_padding_cells * CameraRegion.CELL_SIZE)


func open_map() -> void:
	print("kojsd")
	map_open = true
	camera.frame_rect(world_rect())


func close_map() -> void:
	map_open = false
	if current_region:
		_enter_region(current_region)


func travel_to(r: CameraRegion) -> void:
	map_open = false
	_tracked = null
	_subject = player
	player.global_position = r.get_spawn_position()
	_enter_region(r)


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("toggle_map"):
		if map_open:
			close_map()
		else:
			open_map()
		get_viewport().set_input_as_handled()
		return

	if not map_open:
		return

	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var r := region_at(get_global_mouse_position())
		if r and r.is_travel_target() and r != current_region:
			travel_to(r)
		get_viewport().set_input_as_handled()
