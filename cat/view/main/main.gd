extends Node2D

# Main shell scene for camera panning and scene display

@onready var subviewport: SubViewport = $SubViewport
@onready var viewport_display: TextureRect = $ViewportDisplay
@onready var crt_filter: ColorRect = $CRTFilter
@onready var fog_border: ColorRect = $FogBorder
@onready var smoke_atmosphere: ColorRect = $SmokeAtmosphere
@onready var camera: Camera2D = $SubViewport/Camera2D
@onready var water_background: ColorRect = $SubViewport/WaterBackground
@onready var hex_map = $SubViewport/Hex
#; TEST
@onready var play_hand = $SubViewport/PlayHand
@onready var tile_info = $TileInfo
@onready var topbar_uiux = $TopbarUIUX
@onready var entity_stats_panel = $EntityStatsPanel
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

# Player ULID (represents the current player)
var player_ulid: PackedByteArray = PackedByteArray()

#### TEST ####
# Viking ship testing
var test_vikings: Array = []
var viking_move_timer: float = 0.0
var viking_move_interval: float = 2.0
var occupied_tiles: Dictionary = {}  # Track which tiles have ships

# Jezza NPC testing
var test_jezzas: Array = []
var jezza_move_timer: float = 0.0
var jezza_move_interval: float = 3.0  # Move every 3 seconds

# Fantasy Warrior NPC testing
var test_fantasy_warriors: Array = []
var fantasy_warrior_move_timer: float = 0.0
var fantasy_warrior_move_interval: float = 2.5  # Move every 2.5 seconds

# King NPC testing
var test_kings: Array = []
var king_move_timer: float = 0.0
var king_move_interval: float = 2.0  # Move every 2 seconds

func _ready():
	# Generate player ULID (represents the current player)
	if UlidManager:
		player_ulid = UlidManager.generate()
		print("Main: Player ULID generated: %s" % UlidManager.to_hex(player_ulid))

	# Show language selector immediately (before any initialization)
	_show_language_selector_overlay()

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
	# Connect camera to topbar for CityVote button
	topbar_uiux.camera = camera

	# Connect card signals to control camera panning
	play_hand.card_picked_up.connect(_on_card_picked_up)
	play_hand.card_placed.connect(_on_card_placed)
	play_hand.card_cancelled.connect(_on_card_cancelled)
	#; TEST

	#### TEST ####
	# Initialize Rust pathfinding map cache
	print("Initializing Rust ship pathfinding map cache...")
	get_node("/root/ShipPathfindingBridge").init_map(hex_map)

	print("Initializing Rust NPC pathfinding map cache...")
	get_node("/root/NpcPathfindingBridge").init_map(hex_map)

	# Spawn a few test viking ships on water tiles
	_spawn_test_vikings()

	# Spawn test Jezza raptor on land tiles
	_spawn_test_jezza()

	# Spawn test Fantasy Warriors on land tiles
	_spawn_test_fantasy_warriors()

	# Spawn test Kings on land tiles
	_spawn_test_kings()

	# Connect to joker consumption signal
	if CardComboBridge:
		CardComboBridge.joker_consumed.connect(_on_joker_consumed)
		print("Main: Connected to joker_consumed signal")

	# Test toast notification
	Toast.show_toast(I18n.translate("game.welcome"), 5.0)
	await get_tree().create_timer(2.0).timeout
	Toast.show_toast(I18n.translate("game.entities_spawned"), 3.0)

## Show language selector overlay (shows every time, game is visible behind it)
func _show_language_selector_overlay() -> void:
	# Load language selector scene
	var selector_scene = load("res://view/hud/i18n/language_selector.tscn")
	if not selector_scene:
		push_error("Main: Failed to load language selector scene!")
		return

	var selector = selector_scene.instantiate()
	add_child(selector)

	# Connect to language_selected signal to start timer
	if selector.has_signal("language_selected"):
		selector.language_selected.connect(_on_language_selected)

	print("Main: Language selector displayed over game world")

## Handle language selection - start the game timer
func _on_language_selected(language: int) -> void:
	print("Main: Language selected (%d), starting game timer..." % language)

	# Start the game timer now that player is ready
	if GameTimer:
		GameTimer.start_timer()
		print("Main: Game timer started!")

# === Card Signal Handlers ===
func _on_card_picked_up() -> void:
	# Keep manual panning enabled - auto-follow and manual work together
	print("Card picked up - auto-follow active, manual drag still available")

func _on_card_placed() -> void:
	print("Card placed")

func _on_card_cancelled() -> void:
	print("Card cancelled")

func _calculate_camera_bounds():
	# Calculate bounds by checking all 4 corners using MapConfig
	var top_left_tile = Vector2i(0, 0)
	var top_right_tile = Vector2i(MapConfig.MAP_WIDTH - 1, 0)
	var bottom_left_tile = Vector2i(0, MapConfig.MAP_HEIGHT - 1)
	var bottom_right_tile = Vector2i(MapConfig.MAP_WIDTH - 1, MapConfig.MAP_HEIGHT - 1)

	var top_left_world = hex_map.tile_map.map_to_local(top_left_tile)
	var top_right_world = hex_map.tile_map.map_to_local(top_right_tile)
	var bottom_left_world = hex_map.tile_map.map_to_local(bottom_left_tile)
	var bottom_right_world = hex_map.tile_map.map_to_local(bottom_right_tile)

	print("=== CORNER WATER TILES ===")
	print("Top-Left (0,0): ", top_left_world)
	print("Top-Right (49,0): ", top_right_world)
	print("Bottom-Left (0,49): ", bottom_left_world)
	print("Bottom-Right (49,49): ", bottom_right_world)

	# Account for viewport size
	var viewport_size = Vector2(subviewport.size)
	var viewport_half_size = (viewport_size / camera.zoom) / 2.0
	print("Viewport size: ", viewport_size, " Zoom: ", camera.zoom, " Half size in world: ", viewport_half_size)

	# Find actual min/max from all corners
	var min_world_x = min(min(top_left_world.x, top_right_world.x), min(bottom_left_world.x, bottom_right_world.x)) + 100
	var max_world_x = max(max(top_left_world.x, top_right_world.x), max(bottom_left_world.x, bottom_right_world.x)) - 100
	var min_world_y = min(min(top_left_world.y, top_right_world.y), min(bottom_left_world.y, bottom_right_world.y)) + 50
	var max_world_y = max(max(top_left_world.y, top_right_world.y), max(bottom_left_world.y, bottom_right_world.y)) - 50

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
	# Keep water background centered on camera and scale it with zoom
	# Offset by half the size to center it (ColorRect draws from top-left)
	var zoom_scale = 1.0 / camera.zoom.x
	water_background.position = camera.position - Vector2(640, 360) * zoom_scale
	water_background.scale = Vector2(zoom_scale, zoom_scale)

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

	# Move Jezza NPCs periodically
	jezza_move_timer += delta
	if jezza_move_timer >= jezza_move_interval:
		jezza_move_timer = 0.0
		_move_test_jezzas()

	# Move Fantasy Warrior NPCs periodically
	fantasy_warrior_move_timer += delta
	if fantasy_warrior_move_timer >= fantasy_warrior_move_interval:
		fantasy_warrior_move_timer = 0.0
		_move_test_fantasy_warriors()

	# Move King NPCs periodically
	king_move_timer += delta
	if king_move_timer >= king_move_interval:
		king_move_timer = 0.0
		_move_test_kings()

func _input(event):
	# Handle right-click to open entity stats panel
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			# Get world position of click
			var world_pos = camera.get_global_mouse_position()

			# Find entity near click position (spatial query with generous radius)
			var entity = _find_entity_near_position(world_pos, 32.0)  # 32px search radius

			if entity:
				# Debug: Print entity type
				print("DEBUG: Clicked entity type: ", entity.get_class())
				if entity.get_script():
					print("DEBUG: Entity script global name: ", entity.get_script().get_global_name())

				# Get entity name (translated)
				var entity_name = "Unknown"
				if entity is Ship:
					entity_name = I18n.translate("entity.viking.name")
				elif entity is Jezza:
					entity_name = I18n.translate("entity.jezza_raptor")
				elif entity is FantasyWarrior:
					entity_name = I18n.translate("entity.fantasy_warrior.name")
				elif entity is King:
					entity_name = I18n.translate("entity.king.name")
				elif entity is NPC:
					var script = entity.get_script()
					if script:
						var class_name_val = script.get_global_name()
						if not class_name_val.is_empty():
							entity_name = class_name_val
						else:
							entity_name = "NPC"
					else:
						entity_name = "NPC"

				# Show stats panel
				if entity_stats_panel and "ulid" in entity:
					entity_stats_panel.show_entity_stats(entity, entity.ulid, entity_name)
					get_viewport().set_input_as_handled()

				return

	# Handle mouse drag panning (works alongside auto-follow)
	# Left-click drag works for camera since card placement uses double-click
	if event is InputEventMouseButton:
		var allowed_buttons = [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]

		if event.button_index in allowed_buttons:
			if event.pressed:
				# Don't enable dragging if mouse is over hand UI
				var mouse_pos = get_viewport().get_mouse_position()
				var hand_rect = play_hand.hand_container.get_global_rect()
				if not hand_rect.has_point(mouse_pos):
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

	# Handle trackpad pinch-to-zoom (macOS)
	elif event is InputEventMagnifyGesture:
		var zoom_delta = (event.factor - 1.0) * 0.5  # Scale down sensitivity
		var new_zoom = camera.zoom + Vector2(zoom_delta, zoom_delta)
		new_zoom.x = clamp(new_zoom.x, min_zoom, max_zoom)
		new_zoom.y = clamp(new_zoom.y, min_zoom, max_zoom)
		camera.zoom = new_zoom

#### TEST ####
func _spawn_test_vikings():
	# Find water tiles and spawn vikings on them
	var water_tiles: Array = []

	# Collect all water tile coordinates using MapConfig
	for x in range(MapConfig.MAP_WIDTH):
		for y in range(MapConfig.MAP_HEIGHT):
			var tile_coords = Vector2i(x, y)
			var source_id = hex_map.tile_map.get_cell_source_id(0, tile_coords)
			if source_id == MapConfig.SOURCE_ID_WATER:  # Water tile
				water_tiles.append(tile_coords)

	print("=== VIKING SPAWN ===")
	print("Found ", water_tiles.size(), " water tiles")

	if water_tiles.size() < 10:
		print("Not enough water tiles to spawn vikings")
		return

	# Spawn 10 vikings on random water tiles
	for i in range(10):
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

			# Spawn using EntityManager (handles health bar setup)
			var spawn_config = {
				"direction": randi() % 16,
				"occupied_tiles": occupied_tiles
			}

			EntityManager.spawn_entity(viking, hex_map, world_pos, spawn_config)

			# Apply wave shader to viking (they're on water!)
			_apply_wave_shader_to_viking(viking)

			# Mark tile as occupied
			occupied_tiles[random_tile] = viking

			# Store viking and its current tile
			test_vikings.append({"entity": viking, "tile": random_tile})
			print("Spawned viking ", i, " at tile ", random_tile, " world pos ", world_pos)
		else:
			print("Failed to acquire viking ", i, " from Cluster")

	print("Total vikings spawned: ", test_vikings.size())

func _move_test_vikings():
	# Move each viking using Rust pathfinding
	for i in range(test_vikings.size()):
		var viking_data = test_vikings[i]
		var viking = viking_data["entity"]  # Vikings are Ship instances
		var current_tile = viking_data["tile"]

		# Skip if still moving
		if viking.is_moving:
			continue

		# Find a random destination within range (keeping GDScript for destination picking)
		var destination = Pathfinding.find_random_destination(
			current_tile,
			hex_map,
			occupied_tiles,
			viking,
			3,  # min_distance - encourage longer movements
			10  # max_distance - much larger range for more natural paths
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
				continue  # No valid tiles found

		# Use Rust pathfinding (async via callback)
		var ship_ulid = viking.ulid
		var pathfinding_bridge = get_node("/root/ShipPathfindingBridge")

		# Update ship position in Rust
		pathfinding_bridge.update_ship_position(ship_ulid, current_tile)

		# Request pathfinding from Rust
		pathfinding_bridge.request_path(
			ship_ulid,
			current_tile,
			destination,
			true,  # avoid_ships = true
			func(path: Array[Vector2i], success: bool, _cost: float):
				# Callback when path is found
				if success and path.size() > 1:
					# Free up current tile
					occupied_tiles.erase(current_tile)

					# Capture final destination BEFORE ship clears the path
					var final_destination = path[path.size() - 1]

					# Mark ship as MOVING in Rust
					pathfinding_bridge.set_ship_moving(ship_ulid)

					# Follow the full path calculated by Rust
					viking.follow_path(
						path,
						hex_map.tile_map,
						func():  # On path complete
							# Update occupied tiles
							occupied_tiles[final_destination] = viking
							viking_data["tile"] = final_destination

							# Update Rust with final position and set to IDLE
							pathfinding_bridge.update_ship_position(ship_ulid, final_destination)
							pathfinding_bridge.set_ship_idle(ship_ulid),
						func(waypoint: Vector2i):  # On each waypoint reached
							# Update Rust as ship moves through path
							pathfinding_bridge.update_ship_position(ship_ulid, waypoint)
					)
		)

func _move_test_jezzas():
	# Move each Jezza using Rust NPC pathfinding
	for i in range(test_jezzas.size()):
		var jezza_data = test_jezzas[i]
		var jezza = jezza_data["entity"]  # Jezzas are NPC instances
		var current_tile = jezza_data["tile"]

		# Skip if still moving
		if jezza.is_moving:
			continue

		# Find a random land destination within range
		var destination = _find_random_land_destination(current_tile, 3, 8)

		# If no destination found or same as current, skip
		if destination == current_tile:
			continue

		# Use Rust NPC pathfinding (async via callback)
		var npc_id = jezza.get_instance_id()
		var npc_pathfinding_bridge = get_node("/root/NpcPathfindingBridge")

		# Request pathfinding from Rust
		npc_pathfinding_bridge.request_path(
			npc_id,
			current_tile,
			destination,
			func(path: Array[Vector2i], success: bool):
				# Callback when path is found
				if success and path.size() > 1:
					# Free up current tile
					occupied_tiles.erase(current_tile)

					# Capture final destination
					var final_destination = path[path.size() - 1]

					# Follow the full path calculated by Rust
					jezza.follow_path(
						path,
						hex_map.tile_map,
						func():  # On path complete
							# Update occupied tiles
							occupied_tiles[final_destination] = jezza
							jezza_data["tile"] = final_destination
					)
		)

func _move_test_fantasy_warriors():
	# Move each Fantasy Warrior using Rust NPC pathfinding
	for i in range(test_fantasy_warriors.size()):
		var warrior_data = test_fantasy_warriors[i]
		var warrior = warrior_data["entity"]  # Warriors are NPC instances
		var current_tile = warrior_data["tile"]

		# Skip if still moving
		if warrior.is_moving:
			continue

		# Find a random land destination within range
		var destination = _find_random_land_destination(current_tile, 3, 8)

		# If no destination found or same as current, skip
		if destination == current_tile:
			continue

		# Use Rust NPC pathfinding (async via callback)
		var npc_id = warrior.get_instance_id()
		var npc_pathfinding_bridge = get_node("/root/NpcPathfindingBridge")

		# Request pathfinding from Rust
		npc_pathfinding_bridge.request_path(
			npc_id,
			current_tile,
			destination,
			func(path: Array[Vector2i], success: bool):
				# Callback when path is found
				if success and path.size() > 1:
					# Free up current tile
					occupied_tiles.erase(current_tile)

					# Capture final destination
					var final_destination = path[path.size() - 1]

					# Follow the full path calculated by Rust
					warrior.follow_path(
						path,
						hex_map.tile_map,
						func():  # On path complete
							# Update occupied tiles
							occupied_tiles[final_destination] = warrior
							warrior_data["tile"] = final_destination
					)
		)

func _move_test_kings():
	# Move each King using Rust NPC pathfinding
	for i in range(test_kings.size()):
		var king_data = test_kings[i]
		var king = king_data["entity"]  # Kings are NPC instances
		var current_tile = king_data["tile"]

		# Skip if still moving
		if king.is_moving:
			continue

		# Find a random land destination within range
		var destination = _find_random_land_destination(current_tile, 3, 8)

		# If no destination found or same as current, skip
		if destination == current_tile:
			continue

		# Use Rust NPC pathfinding (async via callback)
		var npc_id = king.get_instance_id()
		var npc_pathfinding_bridge = get_node("/root/NpcPathfindingBridge")

		# Request pathfinding from Rust
		npc_pathfinding_bridge.request_path(
			npc_id,
			current_tile,
			destination,
			func(path: Array[Vector2i], success: bool):
				# Callback when path is found
				if success and path.size() > 1:
					# Free up current tile
					occupied_tiles.erase(current_tile)

					# Capture final destination
					var final_destination = path[path.size() - 1]

					# Follow the full path calculated by Rust
					king.follow_path(
						path,
						hex_map.tile_map,
						func():  # On path complete
							# Update occupied tiles
							occupied_tiles[final_destination] = king
							king_data["tile"] = final_destination
					)
		)

func _find_random_land_destination(start: Vector2i, min_dist: int, max_dist: int) -> Vector2i:
	# Find a random land tile (non-water) within distance range
	var candidates: Array[Vector2i] = []

	for dx in range(-max_dist, max_dist + 1):
		for dy in range(-max_dist, max_dist + 1):
			var test_tile = start + Vector2i(dx, dy)

			# Check if within map bounds
			if test_tile.x < 0 or test_tile.x >= MapConfig.MAP_WIDTH:
				continue
			if test_tile.y < 0 or test_tile.y >= MapConfig.MAP_HEIGHT:
				continue

			# Check distance
			var dist = abs(dx) + abs(dy)
			if dist < min_dist or dist > max_dist:
				continue

			# Check if land tile (not water, source_id != 4)
			var source_id = hex_map.tile_map.get_cell_source_id(0, test_tile)
			if source_id == MapConfig.SOURCE_ID_WATER:  # Water
				continue

			# Check if not occupied
			if occupied_tiles.has(test_tile):
				continue

			candidates.append(test_tile)

	if candidates.size() > 0:
		return candidates[randi() % candidates.size()]

	return start  # No valid destination found

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

func _spawn_test_jezza():
	# Find land tiles (non-water) and spawn Jezza
	var land_tiles: Array = []

	# Collect all land tile coordinates
	for x in range(MapConfig.MAP_WIDTH):
		for y in range(MapConfig.MAP_HEIGHT):
			var tile_coords = Vector2i(x, y)
			var source_id = hex_map.tile_map.get_cell_source_id(0, tile_coords)
			if source_id != 4:  # Not water = land
				land_tiles.append(tile_coords)

	print("=== JEZZA SPAWN ===")
	print("Found ", land_tiles.size(), " land tiles")

	if land_tiles.size() < 3:
		print("Not enough land tiles to spawn Jezza")
		return

	# Spawn 3 Jezza raptors on random land tiles
	for i in range(3):
		var jezza = Cluster.acquire("jezza")
		if jezza:
			# Get random unoccupied land tile
			var random_tile: Vector2i
			var attempts = 0
			while attempts < 100:
				random_tile = land_tiles[randi() % land_tiles.size()]
				if not occupied_tiles.has(random_tile):
					break
				attempts += 1

			# Convert tile coordinates to world position
			var world_pos = hex_map.tile_map.map_to_local(random_tile)

			# Spawn using EntityManager (handles health bar setup)
			var spawn_config = {
				"direction": randi() % 16,
				"occupied_tiles": occupied_tiles
			}

			EntityManager.spawn_entity(jezza, hex_map, world_pos, spawn_config)

			# Mark tile as occupied
			occupied_tiles[random_tile] = jezza

			# Store jezza and its current tile
			test_jezzas.append({"entity": jezza, "tile": random_tile})
			print("Spawned Jezza ", i, " at tile ", random_tile, " world pos ", world_pos)
		else:
			print("Failed to acquire Jezza ", i, " from Cluster")

	print("Total Jezza raptors spawned: 3")

func _spawn_test_fantasy_warriors():
	# Find land tiles (non-water) and spawn Fantasy Warriors
	var land_tiles: Array = []

	# Collect all land tile coordinates
	for x in range(MapConfig.MAP_WIDTH):
		for y in range(MapConfig.MAP_HEIGHT):
			var tile_coords = Vector2i(x, y)
			var source_id = hex_map.tile_map.get_cell_source_id(0, tile_coords)
			if source_id != 4:  # Not water = land
				land_tiles.append(tile_coords)

	print("=== FANTASY WARRIOR SPAWN ===")
	print("Found ", land_tiles.size(), " land tiles")

	if land_tiles.size() < 3:
		print("Not enough land tiles to spawn Fantasy Warriors")
		return

	# Spawn 3 Fantasy Warriors on random land tiles
	for i in range(3):
		var warrior = Cluster.acquire("fantasywarrior")
		if warrior:
			# Get random unoccupied land tile
			var random_tile: Vector2i
			var attempts = 0
			while attempts < 100:
				random_tile = land_tiles[randi() % land_tiles.size()]
				if not occupied_tiles.has(random_tile):
					break
				attempts += 1

			# Convert tile coordinates to world position
			var world_pos = hex_map.tile_map.map_to_local(random_tile)

			# Spawn using EntityManager (handles health bar setup)
			var spawn_config = {
				"direction": randi() % 16,
				"occupied_tiles": occupied_tiles
			}

			EntityManager.spawn_entity(warrior, hex_map, world_pos, spawn_config)

			# Mark tile as occupied
			occupied_tiles[random_tile] = warrior

			# Store warrior and its current tile
			test_fantasy_warriors.append({"entity": warrior, "tile": random_tile})
			print("Spawned Fantasy Warrior ", i, " at tile ", random_tile, " world pos ", world_pos)
		else:
			print("Failed to acquire Fantasy Warrior ", i, " from Cluster")

	print("Total Fantasy Warriors spawned: 3")

func _spawn_test_kings():
	# Find land tiles (non-water) and spawn Kings
	var land_tiles: Array = []

	# Collect all land tile coordinates
	for x in range(MapConfig.MAP_WIDTH):
		for y in range(MapConfig.MAP_HEIGHT):
			var tile_coords = Vector2i(x, y)
			var source_id = hex_map.tile_map.get_cell_source_id(0, tile_coords)
			if source_id != MapConfig.SOURCE_ID_WATER:  # Not water = land
				land_tiles.append(tile_coords)

	print("=== KING SPAWN ===")
	print("Found ", land_tiles.size(), " land tiles")

	if land_tiles.size() < 3:
		print("Not enough land tiles to spawn Kings")
		return

	# Spawn 3 Kings on random land tiles
	for i in range(3):
		var king = Cluster.acquire("king")
		if king:
			# Get random unoccupied land tile
			var random_tile: Vector2i
			var attempts = 0
			while attempts < 100:
				random_tile = land_tiles[randi() % land_tiles.size()]
				if not occupied_tiles.has(random_tile):
					break
				attempts += 1

			# Convert tile coordinates to world position
			var world_pos = hex_map.tile_map.map_to_local(random_tile)

			# Set up spawn configuration
			var spawn_config = {
				"hex_map": hex_map,
				"tile_map": hex_map.tile_map,
				"occupied_tiles": occupied_tiles
			}

			EntityManager.spawn_entity(king, hex_map, world_pos, spawn_config)

			# Mark tile as occupied
			occupied_tiles[random_tile] = king

			# Store king and its current tile
			test_kings.append({"entity": king, "tile": random_tile})
			print("Spawned King ", i, " at tile ", random_tile, " world pos ", world_pos)
		else:
			print("Failed to acquire King ", i, " from Cluster")

	print("Total Kings spawned: 3")

# Find entity near a world position (spatial query)
func _find_entity_near_position(world_pos: Vector2, search_radius: float) -> Node:
	var closest_entity = null
	var closest_distance = search_radius

	# Search through all ships
	for ship_data in test_vikings:
		var ship = ship_data["entity"]  # Vikings are Ship instances
		if ship and is_instance_valid(ship):
			var distance = ship.position.distance_to(world_pos)
			if distance < closest_distance:
				closest_distance = distance
				closest_entity = ship

	# Search through all Jezza NPCs
	for npc_data in test_jezzas:
		var npc = npc_data["entity"]  # Jezzas are NPC instances
		if npc and is_instance_valid(npc):
			var distance = npc.position.distance_to(world_pos)
			if distance < closest_distance:
				closest_distance = distance
				closest_entity = npc

	# Search through all Fantasy Warrior NPCs
	for warrior_data in test_fantasy_warriors:
		var warrior = warrior_data["entity"]  # Warriors are NPC instances
		if warrior and is_instance_valid(warrior):
			var distance = warrior.position.distance_to(world_pos)
			if distance < closest_distance:
				closest_distance = distance
				closest_entity = warrior

	# Search through all King NPCs
	for king_data in test_kings:
		var king = king_data["entity"]  # Kings are NPC instances
		if king and is_instance_valid(king):
			var distance = king.position.distance_to(world_pos)
			if distance < closest_distance:
				closest_distance = distance
				closest_entity = king

	return closest_entity

## Handle joker consumption from combos
func _on_joker_consumed(joker_type: String, joker_card_id: int, count: int, spawn_x: int, spawn_y: int) -> void:
	print("Main: Joker consumed - %s (x%d) at card position (%d, %d)" % [joker_type, count, spawn_x, spawn_y])

	# Card position where joker was placed
	var card_pos = Vector2i(spawn_x, spawn_y)

	match joker_type:
		"JEZZA":
			# Spawn 3 Jezza raptors per card (count × 3)
			var total_jezzas = count * 3
			EntityManager.spawn_multiple({
				"pool_key": "jezza",
				"count": total_jezzas,
				"tile_type": EntityManager.TileType.LAND,
				"hex_map": hex_map,
				"tile_map": hex_map.tile_map,
				"occupied_tiles": occupied_tiles,
				"storage_array": test_jezzas,
				"player_ulid": player_ulid,
				"near_pos": card_pos,
				"entity_name": "Jezza"
			})
			Toast.show_toast("Spawned %d Jezza Raptors!" % total_jezzas, 3.0)
		"VIKING":
			# Spawn 3 viking ships per card (count × 3)
			var total_vikings = count * 3
			EntityManager.spawn_multiple({
				"pool_key": "viking",
				"count": total_vikings,
				"tile_type": EntityManager.TileType.WATER,
				"hex_map": hex_map,
				"tile_map": hex_map.tile_map,
				"occupied_tiles": occupied_tiles,
				"storage_array": test_vikings,
				"player_ulid": player_ulid,
				"near_pos": card_pos,
				"entity_name": "Viking",
				"post_spawn_callback": _apply_wave_shader_to_viking
			})
			Toast.show_toast("Spawned %d Viking Ships!" % total_vikings, 3.0)
		_:
			push_warning("Main: Unknown joker type: %s" % joker_type)
