@tool
class_name CameraRegion
extends Node2D

const CELL_SIZE: int = Constants.GRID_SIZE

enum Mode {
	FRAME,  ## Fit the whole region on screen. Islands.
	FOLLOW, ## Track the subject at a fixed zoom, clamped to this region. Long flights.
}

@export var mode: Mode = Mode.FRAME:
	set(v):
		mode = v
		queue_redraw()

@export var region_name: String = ""

## Region size in grid cells, measured from this node's position (top-left corner).
## Regions are meant to sit flush against each other; Rect2.has_point excludes the
## right and bottom edges, so a shared boundary is never claimed twice.
@export var size_cells: Vector2i = Vector2i(10, 15):
	set(v):
		size_cells = Vector2i(maxi(v.x, 1), maxi(v.y, 1))
		queue_redraw()

@export_group("Frame mode")
## Breathing room added around the region when fitting it to the screen, in cells.
@export var padding_cells: float = 1.0:
	set(v):
		padding_cells = v
		queue_redraw()

## Where map travel drops the blob, in cells from the top-left corner.
@export var spawn_cell: Vector2i = Vector2i.ZERO:
	set(v):
		spawn_cell = v
		queue_redraw()

@export_group("Follow mode")
## How many cells tall the view is while tracking the subject through this region.
@export var view_height_cells: float = 15.0:
	set(v):
		view_height_cells = maxf(v, 1.0)
		queue_redraw()

## Resets to false every launch — there's no save system to persist it across
## sessions right now. Fine for fast-travel gating within a single play session.
var visited: bool = false


func world_size() -> Vector2:
	return Vector2(size_cells) * CELL_SIZE


func get_bounds() -> Rect2:
	return Rect2(global_position, world_size())


func get_frame_rect() -> Rect2:
	return get_bounds().grow(padding_cells * CELL_SIZE)


func get_view_height() -> float:
	return view_height_cells * CELL_SIZE


func get_spawn_position() -> Vector2:
	# Cell centre, matching how the rest of the game resolves positions.
	return global_position + (Vector2(spawn_cell) + Vector2(0.5, 0.5)) * CELL_SIZE


func contains_point(p: Vector2) -> bool:
	return get_bounds().has_point(p)


## Only islands the blob has actually reached, this session, are fast-travel
## destinations.
func is_travel_target() -> bool:
	return mode == Mode.FRAME and visited


# --- Editor -----------------------------------------------------------------

func _ready() -> void:
	if Engine.is_editor_hint():
		set_notify_transform(true)


func _notification(what: int) -> void:
	if what != NOTIFICATION_TRANSFORM_CHANGED or not Engine.is_editor_hint():
		return
	# Keep regions on the grid so bounds never land mid-cell. Delete if you'd
	# rather place them freely.
	var snapped_pos := position.snapped(Vector2(CELL_SIZE, CELL_SIZE))
	if position != snapped_pos:
		position = snapped_pos
	queue_redraw()


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var r := Rect2(Vector2.ZERO, world_size())
	var tint := Color(0.2, 0.8, 1.0) if mode == Mode.FRAME else Color(1.0, 0.65, 0.2)

	draw_rect(r, Color(tint, 0.12), true)
	draw_rect(r, Color(tint, 0.9), false, 3.0)

	if mode == Mode.FRAME:
		draw_rect(r.grow(padding_cells * CELL_SIZE), Color(1, 1, 1, 0.25), false, 1.0)
		draw_circle((Vector2(spawn_cell) + Vector2(0.5, 0.5)) * CELL_SIZE, CELL_SIZE * 0.2, Color(1.0, 0.85, 0.2, 0.9))
	else:
		# Two guides showing how tall the view will be while tracking through here.
		var mid := r.size.y * 0.5
		var half := get_view_height() * 0.5
		for y in [mid - half, mid + half]:
			draw_line(Vector2(0.0, y), Vector2(r.size.x, y), Color(1, 1, 1, 0.4), 1.0)
