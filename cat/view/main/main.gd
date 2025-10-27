extends Node2D

# Main shell scene for camera panning and scene display

@onready var subviewport: SubViewport = $SubViewport
@onready var viewport_display: TextureRect = $ViewportDisplay
@onready var crt_filter: ColorRect = $CRTFilter
@onready var fog_border: ColorRect = $FogBorder
@onready var smoke_atmosphere: ColorRect = $SmokeAtmosphere
@onready var camera: Camera2D = $SubViewport/Camera2D
@onready var hex_map = $SubViewport/Hex
#; TEST
@onready var play_hand = $SubViewport/PlayHand
@onready var tile_info = $TileInfo
#; TEST

var camera_speed = 300.0
var zoom_speed = 0.1
var min_zoom = 0.5
var max_zoom = 4.0

# Camera bounds (keep camera within land area, away from water border)
# Map is 50x50 tiles at ~32x28 tile size = ~1600x1400 world coords
# Water border is 12 tiles (~384 pixels), land area tiles (12,12) to (38,38)
# Land area in world coords: ~(384, 336) to (~1216, ~1064)
var camera_min_bounds = Vector2(400, 350)  # Left/top edge of land area
var camera_max_bounds = Vector2(1200, 1050)  # Right/bottom edge of land area

# Drag panning variables
var is_dragging = false
var drag_start_mouse_pos = Vector2.ZERO
var drag_start_camera_pos = Vector2.ZERO
var manual_camera_panning_enabled = true  # Controlled by card signals

# CRT effect toggle
var crt_effect = false  # Set to true to enable CRT shader

#### TEST ####
# Viking ship testing
var test_vikings: Array = []
var viking_move_timer: float = 0.0
var viking_move_interval: float = 2.0
var occupied_tiles: Dictionary = {}  # Track which tiles have ships

func _ready():
	# Get viewport texture
	var viewport_texture = subviewport.get_texture()

	# Always display the viewport on the base TextureRect
	viewport_display.texture = viewport_texture

	# Setup CRT shader viewport texture
	crt_filter.material.set_shader_parameter("tex", viewport_texture)

	# Enable/disable CRT effect and fog layers
	crt_filter.visible = crt_effect
	fog_border.visible = crt_effect
	smoke_atmosphere.visible = crt_effect

	# Enable viewport to handle input events
	subviewport.handle_input_locally = false

	# Calculate camera bounds based on actual tilemap (must be done first!)
	_calculate_camera_bounds()

	#; TEST
	# Connect hex_map to play_hand for card placement
	play_hand.hex_map = hex_map
	# Connect camera to play_hand for auto-follow
	play_hand.camera = camera
	# Pass camera bounds to play_hand for proper clamping (after bounds are calculated)
	play_hand.camera_min_bounds = camera_min_bounds
	play_hand.camera_max_bounds = camera_max_bounds
	# Connect hex_map to tile_info for tile hover display
	tile_info.hex_map = hex_map

	# Connect card signals to control camera panning
	play_hand.card_picked_up.connect(_on_card_picked_up)
	play_hand.card_placed.connect(_on_card_placed)
	play_hand.card_cancelled.connect(_on_card_cancelled)
	#; TEST

	#### TEST ####
	# Spawn a few test viking ships on water tiles
	_spawn_test_vikings()

# === Card Signal Handlers ===
func _on_card_picked_up() -> void:
	# Keep manual panning enabled - auto-follow and manual work together
	print("Card picked up - auto-follow active, manual drag still available")

func _on_card_placed() -> void:
	print("Card placed")

func _on_card_cancelled() -> void:
	print("Card cancelled")

func _calculate_camera_bounds():
	# Debug: Find the 4 corner water tiles and print their world positions
	# Top-left corner water tile (should be around 0,0)
	var top_left_tile = Vector2i(0, 0)
	var top_left_world = hex_map.tile_map.map_to_local(top_left_tile)

	# Top-right corner water tile
	var top_right_tile = Vector2i(49, 0)
	var top_right_world = hex_map.tile_map.map_to_local(top_right_tile)

	# Bottom-left corner water tile
	var bottom_left_tile = Vector2i(0, 49)
	var bottom_left_world = hex_map.tile_map.map_to_local(bottom_left_tile)

	# Bottom-right corner water tile
	var bottom_right_tile = Vector2i(49, 49)
	var bottom_right_world = hex_map.tile_map.map_to_local(bottom_right_tile)

	print("=== CORNER WATER TILES ===")
	print("Top-Left (0,0): ", top_left_world)
	print("Top-Right (49,0): ", top_right_world)
	print("Bottom-Left (0,49): ", bottom_left_world)
	print("Bottom-Right (49,49): ", bottom_right_world)

	# Also print the land area corners (12,12) and (37,37)
	var land_top_left = hex_map.tile_map.map_to_local(Vector2i(12, 12))
	var land_bottom_right = hex_map.tile_map.map_to_local(Vector2i(37, 37))
	print("=== LAND AREA ===")
	print("Land Top-Left (12,12): ", land_top_left)
	print("Land Bottom-Right (37,37): ", land_bottom_right)

	# Based on actual corner coordinates:
	# Map spans X: -1160 to 1192, Y: 14 to 1386
	# Land area centered at X: 16, Y: 350 to 1050

	# Account for viewport size (dynamically based on actual viewport and zoom)
	var viewport_size = Vector2(subviewport.size)  # Convert Vector2i to Vector2
	var viewport_half_size = (viewport_size / camera.zoom) / 2.0
	print("Viewport size: ", viewport_size, " Zoom: ", camera.zoom, " Half size in world: ", viewport_half_size)

	# Set bounds to allow viewing the entire map (water included)
	# Use minimal padding so camera can reach all tiles
	var min_world_x = -1160.0 + 100  # Left water edge with small padding
	var max_world_x = 1192.0 - 100   # Right water edge with small padding
	var min_world_y = 14.0 + 50      # Top water edge with small padding
	var max_world_y = 1386.0 - 50    # Bottom water edge with small padding

	camera_min_bounds = Vector2(min_world_x, min_world_y) + viewport_half_size
	camera_max_bounds = Vector2(max_world_x, max_world_y) - viewport_half_size

	print("=== CAMERA ===")
	print("Camera bounds: ", camera_min_bounds, " to ", camera_max_bounds)
	print("Camera starting position: ", camera.position)
	print("Usable camera area width: ", camera_max_bounds.x - camera_min_bounds.x)

func _unhandled_input(event):
	# Forward input events to the SubViewport
	if event is InputEventMouse:
		# Mouse events need to be cloned and positioned correctly for the viewport
		var cloned_event = event.duplicate()
		# The viewport is 1:1 with screen space since CRTFilter just applies shader
		# No transformation needed - viewport matches window size
		subviewport.push_input(cloned_event, true)

func _process(delta):
	# Handle drag panning
	if is_dragging:
		var current_mouse_pos = get_viewport().get_mouse_position()
		var mouse_delta = (current_mouse_pos - drag_start_mouse_pos) / camera.zoom.x
		var new_pos = drag_start_camera_pos - mouse_delta
		camera.position = _clamp_camera_position(new_pos)

	#; TEST
	# Camera panning with arrow keys or WASD (works even when dragging a card!)
	var direction = Vector2.ZERO

	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		direction.x += 1
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		direction.x -= 1
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		direction.y += 1
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		direction.y -= 1

	if direction != Vector2.ZERO:
		var new_pos = camera.position + direction.normalized() * camera_speed * delta / camera.zoom.x
		camera.position = _clamp_camera_position(new_pos)
	#; TEST

	#### TEST ####
	# Move vikings periodically
	viking_move_timer += delta
	if viking_move_timer >= viking_move_interval:
		viking_move_timer = 0.0
		_move_test_vikings()

func _input(event):
	# Handle mouse drag panning (works alongside auto-follow)
	# Left-click drag works for camera since card placement uses double-click
	if event is InputEventMouseButton:
		var allowed_buttons = [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]

		if event.button_index in allowed_buttons:
			if event.pressed:
				is_dragging = true
				drag_start_mouse_pos = event.position
				drag_start_camera_pos = camera.position
			else:
				is_dragging = false

		# Zoom with mouse wheel
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			var new_zoom = camera.zoom + Vector2(zoom_speed, zoom_speed)
			if new_zoom.x <= max_zoom:
				camera.zoom = new_zoom
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			var new_zoom = camera.zoom - Vector2(zoom_speed, zoom_speed)
			if new_zoom.x >= min_zoom:
				camera.zoom = new_zoom

	# Handle touch drag panning (for mobile/touch devices)
	elif event is InputEventScreenTouch:
		if event.pressed:
			is_dragging = true
			drag_start_mouse_pos = event.position
			drag_start_camera_pos = camera.position
		else:
			is_dragging = false

#### TEST ####
func _spawn_test_vikings():
	# Find water tiles and spawn 3 vikings on them
	var water_tiles: Array = []

	# Collect all water tile coordinates
	for x in range(50):
		for y in range(50):
			var tile_coords = Vector2i(x, y)
			var source_id = hex_map.tile_map.get_cell_source_id(0, tile_coords)
			if source_id == 4:  # Water tile
				water_tiles.append(tile_coords)

	print("=== VIKING SPAWN ===")
	print("Found ", water_tiles.size(), " water tiles")

	if water_tiles.size() < 3:
		print("Not enough water tiles to spawn vikings")
		return

	# Spawn 3 vikings on random water tiles
	for i in range(3):
		var viking = Cluster.acquire("viking")
		if viking:
			# Get random unoccupied water tile
			var random_tile: Vector2i
			var attempts = 0
			while attempts < 100:
				random_tile = water_tiles[randi() % water_tiles.size()]
				if not occupied_tiles.has(random_tile):
					break
				attempts += 1

			# Convert tile coordinates to world position
			var world_pos = hex_map.tile_map.map_to_local(random_tile)

			# Set viking position and add to hex_map
			hex_map.add_child(viking)
			viking.position = world_pos
			viking.occupied_tiles = occupied_tiles  # Share reference

			# Apply wave shader to viking (they're on water!)
			_apply_wave_shader_to_viking(viking)

			# Set random initial direction
			viking.set_direction(randi() % 16)

			# Mark tile as occupied
			occupied_tiles[random_tile] = viking

			# Store viking and its current tile
			test_vikings.append({"ship": viking, "tile": random_tile})
			print("Spawned viking ", i, " at tile ", random_tile, " world pos ", world_pos)
		else:
			print("Failed to acquire viking ", i, " from Cluster")

	print("Total vikings spawned: ", test_vikings.size())

func _move_test_vikings():
	print("=== MOVING VIKINGS ===")
	print("Total vikings to move: ", test_vikings.size())

	# Move each viking using pathfinding
	for i in range(test_vikings.size()):
		var viking_data = test_vikings[i]
		var viking = viking_data["ship"]
		var current_tile = viking_data["tile"]

		print("Viking ", i, " at tile ", current_tile, " is_moving: ", viking.is_moving)

		# Skip if still moving
		if viking.is_moving:
			print("  Skipping - still moving")
			continue

		# Find a random destination within range using pathfinding
		var destination = Pathfinding.find_random_destination(
			current_tile,
			hex_map,
			occupied_tiles,
			viking,
			1,  # min_distance
			3   # max_distance
		)

		# If no destination found or same as current, try adjacent tiles
		if destination == current_tile:
			var adjacent_tiles = Pathfinding.find_valid_adjacent_water_tiles(
				current_tile,
				hex_map,
				occupied_tiles,
				viking
			)

			if adjacent_tiles.size() > 0:
				destination = adjacent_tiles[randi() % adjacent_tiles.size()]
			else:
				print("  No valid tiles found - cannot move")
				continue

		# Find path to destination
		var path = Pathfinding.find_path(
			current_tile,
			destination,
			hex_map,
			occupied_tiles,
			viking
		)

		if path.size() > 0:
			# Move to first tile in path
			var new_tile = path[0]
			var new_pos = hex_map.tile_map.map_to_local(new_tile)

			print("  Current viking pos: ", viking.position, " Target pos: ", new_pos)
			var direction_vec = new_pos - viking.position
			print("  Direction vector: ", direction_vec, " Length: ", direction_vec.length(), " Angle: ", rad_to_deg(direction_vec.angle()))

			# Free up current tile
			occupied_tiles.erase(current_tile)

			# Occupy new tile
			occupied_tiles[new_tile] = viking

			# Start smooth movement
			viking.move_to(new_pos)

			# Update stored tile
			viking_data["tile"] = new_tile
			print("  Moving to tile ", new_tile, " at pos ", new_pos, " (path length: ", path.size(), ")")
		else:
			print("  No path found - cannot move")

# Clamp camera position within bounds
# TODO: Implement smooth wrapping with duplicate tiles at edges for seamless looping
func _clamp_camera_position(pos: Vector2) -> Vector2:
	return Vector2(
		clamp(pos.x, camera_min_bounds.x, camera_max_bounds.x),
		clamp(pos.y, camera_min_bounds.y, camera_max_bounds.y)
	)

# Apply wave shader to viking ships
func _apply_wave_shader_to_viking(viking: Node2D) -> void:
	# Create shader material from Cache with parameters
	var shader_material = Cache.create_shader_material("with_wave", {
		"wave_speed": 0.6,
		"wave_amplitude": 1.5,  # Gentle bobbing
		"sway_amplitude": 1.0,  # Subtle sway
		"wave_frequency": 1.2,
		"rotation_amount": 0.8  # Slight rocking
	})

	# Apply to the sprite child
	if shader_material:
		var sprite = viking.get_node("Sprite2D")
		if sprite:
			sprite.material = shader_material
