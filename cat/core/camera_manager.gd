extends Node

## CameraManager - Centralized camera control and positioning
## Provides signals for camera movement and management
## Use this to programmatically move the camera from anywhere in the game

## Signals
signal pan_requested(target_position: Vector2, duration: float, smooth: bool)
signal zoom_requested(target_zoom: Vector2, duration: float)
signal focus_entity_requested(entity: Node)
signal focus_tile_requested(tile_coords: Vector2i)

## Camera reference (set by main scene)
var camera: Camera2D = null

## Pan settings
var default_pan_duration: float = 0.8
var default_pan_smooth: bool = true

## Current pan tween
var pan_tween: Tween = null

func _ready():
	print("CameraManager: Initialized")

## Set the camera reference (called by main scene)
func set_camera(cam: Camera2D) -> void:
	camera = cam
	print("CameraManager: Camera reference set")

## Pan camera to a world position
## @param target_pos: World position to pan to
## @param duration: Animation duration in seconds (default: 0.8)
## @param smooth: Use smooth easing (default: true)
func pan_to_position(target_pos: Vector2, duration: float = -1.0, smooth: bool = true) -> void:
	if not camera:
		push_error("CameraManager: No camera reference set!")
		return

	if duration < 0:
		duration = default_pan_duration

	# Cancel existing tween
	if pan_tween:
		pan_tween.kill()

	# Create new tween
	pan_tween = create_tween()
	if smooth:
		pan_tween.set_ease(Tween.EASE_IN_OUT)
		pan_tween.set_trans(Tween.TRANS_CUBIC)

	# Animate position
	pan_tween.tween_property(camera, "position", target_pos, duration)

	print("CameraManager: Panning to %v over %.2fs" % [target_pos, duration])

	# Emit signal for other systems to react
	pan_requested.emit(target_pos, duration, smooth)

## Pan camera to a tile coordinate
## @param tile_coords: Tile coordinates (Vector2i)
## @param tile_map: TileMapCompat wrapper to convert coords to world position
## @param duration: Animation duration in seconds
func pan_to_tile(tile_coords: Vector2i, tile_map, duration: float = -1.0) -> void:
	if not tile_map:
		push_error("CameraManager: No tile_map provided!")
		return

	var world_pos = tile_map.map_to_local(tile_coords)
	pan_to_position(world_pos, duration)

	focus_tile_requested.emit(tile_coords)

## Pan camera to follow an entity
## @param entity: Entity node to follow
## @param duration: Animation duration in seconds
func pan_to_entity(entity: Node, duration: float = -1.0) -> void:
	if not entity or not is_instance_valid(entity):
		push_error("CameraManager: Invalid entity!")
		return

	pan_to_position(entity.position, duration)
	focus_entity_requested.emit(entity)

## Set camera zoom with animation
## @param target_zoom: Target zoom level (Vector2)
## @param duration: Animation duration in seconds
func set_zoom(target_zoom: Vector2, duration: float = 0.5) -> void:
	if not camera:
		push_error("CameraManager: No camera reference set!")
		return

	# Cancel existing tween
	if pan_tween:
		pan_tween.kill()

	# Create new tween
	pan_tween = create_tween()
	pan_tween.set_ease(Tween.EASE_IN_OUT)
	pan_tween.set_trans(Tween.TRANS_CUBIC)

	# Animate zoom
	pan_tween.tween_property(camera, "zoom", target_zoom, duration)

	print("CameraManager: Zooming to %v over %.2fs" % [target_zoom, duration])

	zoom_requested.emit(target_zoom, duration)

## Instant camera position (no animation)
func set_position_instant(target_pos: Vector2) -> void:
	if not camera:
		push_error("CameraManager: No camera reference set!")
		return

	camera.position = target_pos
	print("CameraManager: Instant position set to %v" % target_pos)
