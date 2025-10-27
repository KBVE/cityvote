extends Node2D

# Main shell scene for camera panning and scene display

@onready var subviewport: SubViewport = $SubViewport
@onready var crt_filter: ColorRect = $CRTFilter
@onready var camera: Camera2D = $SubViewport/Camera2D
@onready var hex_map = $SubViewport/Hex

var camera_speed = 300.0
var zoom_speed = 0.1
var min_zoom = 0.5
var max_zoom = 4.0

# Drag panning variables
var is_dragging = false
var drag_start_mouse_pos = Vector2.ZERO
var drag_start_camera_pos = Vector2.ZERO

#### TEST ####
# Viking ship testing
var test_vikings: Array = []
var viking_move_timer: float = 0.0
var viking_move_interval: float = 2.0
var occupied_tiles: Dictionary = {}  # Track which tiles have ships

func _ready():
	# Setup CRT shader viewport texture
	var viewport_texture = subviewport.get_texture()
	crt_filter.material.set_shader_parameter("tex", viewport_texture)

	# Enable viewport to handle input events
	subviewport.handle_input_locally = false

	#### TEST ####
	# Spawn a few test viking ships on water tiles
	_spawn_test_vikings()

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
		camera.position = drag_start_camera_pos - mouse_delta

	# Camera panning with arrow keys or WASD (only when not dragging)
	if not is_dragging:
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
			camera.position += direction.normalized() * camera_speed * delta / camera.zoom.x

	#### TEST ####
	# Move vikings periodically
	viking_move_timer += delta
	if viking_move_timer >= viking_move_interval:
		viking_move_timer = 0.0
		_move_test_vikings()

func _input(event):
	# Handle mouse drag panning (left/right/middle mouse button)
	if event is InputEventMouseButton:
		# Start dragging with left, right, or middle mouse button
		if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
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
	for x in range(30):
		for y in range(30):
			var tile_coords = Vector2i(x, y)
			var source_id = hex_map.tile_map.get_cell_source_id(0, tile_coords)
			if source_id == 4:  # Water tile
				water_tiles.append(tile_coords)

	if water_tiles.size() < 3:
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

			# Set random initial direction
			viking.set_direction(randi() % 16)

			# Mark tile as occupied
			occupied_tiles[random_tile] = viking

			# Store viking and its current tile
			test_vikings.append({"ship": viking, "tile": random_tile})

func _move_test_vikings():
	# Move each viking to an adjacent water tile
	for viking_data in test_vikings:
		var viking = viking_data["ship"]
		var current_tile = viking_data["tile"]

		# Skip if still moving
		if viking.is_moving:
			continue

		# Get adjacent hex tiles (6 directions for hex grid)
		var adjacent_offsets = [
			Vector2i(1, 0),   # East
			Vector2i(-1, 0),  # West
			Vector2i(0, 1),   # South-East (staggered)
			Vector2i(0, -1),  # North-West (staggered)
			Vector2i(1, -1),  # North-East
			Vector2i(-1, 1),  # South-West
		]

		# Find adjacent water tiles that are unoccupied
		var adjacent_water_tiles: Array = []
		for offset in adjacent_offsets:
			var check_tile = current_tile + offset

			# Check if tile is within bounds and is water
			if check_tile.x >= 0 and check_tile.x < 30 and check_tile.y >= 0 and check_tile.y < 30:
				var source_id = hex_map.tile_map.get_cell_source_id(0, check_tile)
				if source_id == 4:  # Water tile
					# Check if tile is not occupied by another ship
					if not occupied_tiles.has(check_tile) or occupied_tiles[check_tile] == viking:
						adjacent_water_tiles.append(check_tile)

		if adjacent_water_tiles.size() > 0:
			# Move to random adjacent water tile
			var new_tile = adjacent_water_tiles[randi() % adjacent_water_tiles.size()]
			var new_pos = hex_map.tile_map.map_to_local(new_tile)

			# Free up current tile
			occupied_tiles.erase(current_tile)

			# Occupy new tile
			occupied_tiles[new_tile] = viking

			# Start smooth movement
			viking.move_to(new_pos)

			# Update stored tile
			viking_data["tile"] = new_tile
