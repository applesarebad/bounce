class_name World
extends Node2D

## Scene tree this expects:
##   World (world.gd)
##   ├── TileMapLayers (ground / walls-v / walls-h / walls-diag)
##   ├── Regions        <- CameraRegion nodes go here
##   ├── Objects        <- crates, logs, breakable walls; also the spawn_root
##   ├── Player
##   ├── Projectiles    <- optional; see projectile_container below
##   ├── WorldCamera    (world_camera.gd)
##   ├── SaveSystem     (save_system.gd)
##   └── UndoSystem     (undo_system.gd)

enum ProjectileFraming {
	NEVER,          ## The ball never changes which island is framed.
	WHEN_OFFSCREEN, ## Reframe only once the ball is about to leave the view.
	ALWAYS,         ## Reframe the moment the ball crosses into another island.
}

@export var player: Node2D
@export var regions_root: Node
@export var camera: WorldCamera
@export var start_region: CameraRegion
@export var map_padding_cells: float = 2.0

## Optional. If set, the camera picks up whatever enters this node and hands
## itself back to the blob when it leaves. Leave it empty to drive the handoff
## yourself with track() and release().
@export var projectile_container: Node

@export_group("Projectile framing")
## Whether a projectile in flight can change which island is framed. FOLLOW
## regions always engage regardless of this — a long flight needs the camera
## pulled back before it starts, whatever is making the trip.
@export var projectile_framing: ProjectileFraming = ProjectileFraming.WHEN_OFFSCREEN

## Fraction of the view inset from each edge that counts as "about to leave".
@export_range(0.0, 0.4) var offscreen_margin: float = 0.1

## Ball-driven reframes use this instead of the camera's normal transition time.
@export var projectile_transition_time: float = 0.25

@export_group("Saving")
@export var save_system: SaveSystem
@export var undo_system: UndoSystem
@export var save_slot: int = 0
## Turns resolve faster than a disk write is worth doing, so autosaves coalesce
## over this window rather than firing on every move.
@export var autosave_debounce: float = 2.0
## Carry the undo stack in the save file, so a player who ruins an island can
## still back out of it after quitting.
@export var persist_undo: bool = true

## Set by this node on itself, same pattern as SaveableObject.undo below.
## Lets Player/blob reach World without an @export wired through every scene
## that needs it, while still being a real scene-tree node rather than an
## Autoload — it needs @export references to this specific level's player,
## camera and regions, which an Autoload can't hold.
static var instance: World

var regions: Array[CameraRegion] = []
var current_region: CameraRegion
var map_open: bool = false

var _subject: Node2D  ## What the camera is currently watching.
var _tracked: Node2D  ## The projectile, while one is in flight.
var _save_timer: Timer

signal region_changed(region: CameraRegion)


func _ready() -> void:
	for c in regions_root.get_children():
		if c is CameraRegion:
			regions.append(c)

	_subject = player
	SaveableObject.undo = undo_system
	instance = self

	if projectile_container:
		projectile_container.child_entered_tree.connect(_on_projectile_spawned)
		projectile_container.child_exiting_tree.connect(_on_projectile_freed)

	# Load before framing: the save can move the blob, and the region it starts
	# in follows from where the blob actually ends up.
	_setup_saving()

	var start: CameraRegion = start_region
	if start == null:
		start = region_at(player.global_position)
	if start:
		if start.mode == CameraRegion.Mode.FRAME:
			start.visited = true
		_enter_region(start, false)


func _exit_tree() -> void:
	# Static, so it would otherwise outlive this scene and point at a freed node.
	if SaveableObject.undo == undo_system:
		SaveableObject.undo = null
	if instance == self:
		instance = null


# --- Saving -----------------------------------------------------------------

func _setup_saving() -> void:
	if save_system == null:
		return

	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = autosave_debounce
	_save_timer.timeout.connect(save_now)
	add_child(_save_timer)

	# Node _ready() runs children-first, so every authored object is already in
	# the group by the time this runs. The baseline is what the diff measures
	# against, so it has to be taken before any save is applied.
	save_system.capture_baseline()

	var data := save_system.read(save_slot)
	if data.is_empty():
		return
	save_system.apply(data)
	restore_world_state(data.get("world", {}))


## Call when a turn resolves. Cheap — the write itself is debounced, so calling
## it every move is fine.
func request_autosave() -> void:
	if _save_timer:
		_save_timer.start()


func save_now() -> void:
	if save_system:
		save_system.write(save_slot, capture_world_state())


## State that isn't held by an object in the "saveable" group. The undo system
## uses this too, so anything added here is undone as well as saved — put global
## counters like total ball distance in here and both come for free.
##
## current_region is deliberately absent: it follows from where the blob is.
func capture_world_state() -> Dictionary:
	return {
		"player_cell": Vector2i((player.global_position / CameraRegion.CELL_SIZE).floor()),
	}


func restore_world_state(d: Dictionary) -> void:
	if d.has("player_cell"):
		var cell: Vector2i = d["player_cell"]
		player.global_position = (Vector2(cell) + Vector2(0.5, 0.5)) * CameraRegion.CELL_SIZE


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		save_now()


# --- Undo -------------------------------------------------------------------

func request_undo() -> void:
	if undo_system == null or map_open:
		return

	if undo_system.is_turn_open():
		# Mid-flight. Cancel the shot in progress rather than reaching past it to
		# the previous turn — the ball has to stop existing either way, and
		# throwing away a partial turn is cheaper than completing it to undo it.
		_abort_projectile()
		undo_system.cancel_turn()
	elif not undo_system.undo():
		return

	_evaluate_region(true)
	request_autosave()


func _abort_projectile() -> void:
	if _tracked == null:
		return
	var p := _tracked
	# Cleared first so _on_projectile_freed doesn't fire release() and close the
	# turn we're in the middle of cancelling.
	_tracked = null
	_subject = player
	p.queue_free()


# --- Camera subject ---------------------------------------------------------

## Hand the camera to a projectile for the duration of its flight. This is also
## the start of a turn, so everything the shot goes on to disturb lands in one
## undo entry.
func track(node: Node2D) -> void:
	_tracked = node
	_subject = node
	if undo_system:
		undo_system.begin_turn()
	_evaluate_region(true)


## Give the camera back to the blob and re-frame immediately — a turn just ended.
## This is also the only moment the world is at rest, so it's where both the undo
## entry and the autosave belong: every save is a state the player can resume
## from, never a ball halfway through a bounce.
func release() -> void:
	_tracked = null
	_subject = player
	if undo_system:
		undo_system.end_turn()
	_evaluate_region(true)
	request_autosave()


## Subjects can expose get_camera_target() to hand back something other than
## their own origin — the ball offsetting forward along its travel direction so
## you see where it's headed, or the blob returning its smoothed visual position
## rather than the cell it logically occupies. The latter is the clean fix if
## follow mode judders against your tick rate.
func subject_position() -> Vector2:
	if _subject == null:
		return Vector2.ZERO
	if _subject.has_method("get_camera_target"):
		return _subject.get_camera_target()
	return _subject.global_position


func _on_projectile_spawned(n: Node) -> void:
	if n is Node2D:
		track(n)


func _on_projectile_freed(n: Node) -> void:
	if n == _tracked:
		release()


# --- Region tracking --------------------------------------------------------

func _process(_delta: float) -> void:
	if map_open or _subject == null or current_region == null:
		return

	_evaluate_region(false)

	if current_region.mode != CameraRegion.Mode.FOLLOW:
		return

	# Once the subject crosses out of the corridor, widen the clamp to include
	# where it's headed, otherwise the camera stalls at the corridor edge.
	var here := region_at(subject_position())
	var limits := current_region.get_bounds()
	if here and here != current_region:
		limits = limits.merge(here.get_bounds())
	camera.update_follow(subject_position(), limits)


## `allow_frame` marks a moment where the blob's position is authoritative:
## release(), on_player_settled(), and undo. Outside those, a FRAME change is
## only permitted if projectile_framing says the ball may drive one.
##
## A null region (unclaimed water between islands) holds the current framing
## rather than snapping somewhere arbitrary.
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


## Call this once the blob has finished a move and settled on a cell centre.
func on_player_settled() -> void:
	if map_open:
		return

	var here := region_at(player.global_position)

	# Arrival is the blob's business alone — a ball reframing onto an island must
	# not unlock it as a fast-travel destination. Deliberately not undone: having
	# discovered an island isn't a move you take back.
	if here and here.mode == CameraRegion.Mode.FRAME:
		here.visited = true

	# The ball still owns the camera; release() will re-frame when it's done.
	if _tracked != null:
		return

	if here == null or here == current_region:
		return
	_enter_region(here)


## Rect2.has_point excludes the right and bottom edges, so flush regions never
## both claim a boundary point. Where rects genuinely overlap, first match in
## tree order wins — reorder the children to control priority.
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
	map_open = true
	camera.frame_rect(world_rect())


func close_map() -> void:
	map_open = false
	if current_region:
		_enter_region(current_region)


## Wrapped in a turn so the undo stack stays a faithful history. Leaving travel
## out would make every older entry's player_cell a lie, and undoing after a trip
## would teleport the blob back with no explanation.
func travel_to(r: CameraRegion) -> void:
	map_open = false
	_tracked = null
	_subject = player
	if undo_system:
		undo_system.begin_turn()
	player.global_position = r.get_spawn_position()
	if undo_system:
		undo_system.end_turn()
	_enter_region(r)
	request_autosave()


func _unhandled_input(e: InputEvent) -> void:
	# Add "toggle_map" and "undo" actions in Project Settings > Input Map.
	if e.is_action_pressed("undo"):
		request_undo()
		get_viewport().set_input_as_handled()
		return

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
		# get_global_mouse_position() already accounts for camera zoom and position,
		# so no unprojection is needed here.
		var r := region_at(get_global_mouse_position())
		if r and r.is_travel_target() and r != current_region:
			travel_to(r)
		get_viewport().set_input_as_handled()
