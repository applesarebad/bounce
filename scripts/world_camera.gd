class_name WorldCamera
extends Camera2D

@export var transition_time: float = 0.45
@export var transition_trans: Tween.TransitionType = Tween.TRANS_CUBIC
@export var transition_ease: Tween.EaseType = Tween.EASE_IN_OUT

## Cap on magnification, so a tiny island doesn't fill the screen with four cells.
@export var max_zoom: float = 3.0

## How quickly the camera catches up to the subject in FOLLOW regions.
@export var follow_smoothing: float = 6.0

var _target_rect: Rect2
var _follow_view_height: float = 0.0
var _following: bool = false
var _tween: Tween


func _ready() -> void:
	get_viewport().size_changed.connect(_refit)
	position_smoothing_enabled = false


# --- Frame mode -------------------------------------------------------------
func frame_rect(rect: Rect2, animated: bool = true, duration: float = -1.0) -> void:
	_following = false
	position_smoothing_enabled = false
	_target_rect = rect
	_kill_tween()

	var time := transition_time if duration < 0.0 else duration
	var target_zoom := _zoom_for_rect(rect)
	var target_pos := rect.get_center()

	if not animated or time <= 0.0:
		_apply_zoom(target_zoom)
		global_position = target_pos
		return

	_tween = create_tween().set_parallel(true)
	_tween.set_trans(transition_trans).set_ease(transition_ease)
	_tween.tween_property(self, "global_position", target_pos, time)
	_tween.tween_method(_apply_zoom_log, log(zoom.x), log(target_zoom), time)


# --- Follow mode ------------------------------------------------------------

func begin_follow(view_height: float, animated: bool = true) -> void:
	if _following and is_equal_approx(_follow_view_height, view_height):
		return

	_following = true
	_follow_view_height = view_height
	_target_rect = Rect2()
	_kill_tween()

	position_smoothing_enabled = true
	position_smoothing_speed = follow_smoothing

	var target_zoom := _zoom_for_height(view_height)
	if not animated or transition_time <= 0.0:
		_apply_zoom(target_zoom)
		return

	_tween = create_tween()
	_tween.set_trans(transition_trans).set_ease(transition_ease)
	_tween.tween_method(_apply_zoom_log, log(zoom.x), log(target_zoom), transition_time)

func update_follow(point: Vector2, limits: Rect2) -> void:
	if not _following:
		return
	global_position = _clamp_centre(point, limits)


func is_following() -> bool:
	return _following


func is_transitioning() -> bool:
	return _tween != null and _tween.is_running()


func get_visible_world_rect() -> Rect2:
	var size := get_viewport_rect().size / zoom
	return Rect2(get_screen_center_position() - size * 0.5, size)


# --- Internals --------------------------------------------------------------

func _clamp_centre(centre: Vector2, limits: Rect2) -> Vector2:
	var half := (get_viewport_rect().size / zoom) * 0.5
	var lo := limits.position + half
	var hi := limits.end - half
	var mid := limits.get_center()
	var out := centre
	# If the visible area is wider than the region on an axis, centre on it instead.
	out.x = mid.x if lo.x > hi.x else clampf(centre.x, lo.x, hi.x)
	out.y = mid.y if lo.y > hi.y else clampf(centre.y, lo.y, hi.y)
	return out


func _zoom_for_rect(rect: Rect2) -> float:
	var view := get_viewport_rect().size
	return minf(minf(view.x / rect.size.x, view.y / rect.size.y), max_zoom)


func _zoom_for_height(world_height: float) -> float:
	return minf(get_viewport_rect().size.y / world_height, max_zoom)


func _apply_zoom(z: float) -> void:
	zoom = Vector2(z, z)


func _apply_zoom_log(log_z: float) -> void:
	_apply_zoom(exp(log_z))


func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()


func _refit() -> void:
	if _following:
		_kill_tween()
		_apply_zoom(_zoom_for_height(_follow_view_height))
	elif _target_rect.size != Vector2.ZERO:
		frame_rect(_target_rect, false)
