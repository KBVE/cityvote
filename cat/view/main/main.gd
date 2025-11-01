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

var camera_speed = 960.0
var zoom_speed = 0.1
var min_zoom = 0.5
var max_zoom = 4.0

# NOTE: Camera bounds removed for infinite world
# Chunks are generated on-demand based on camera position

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

# Chunk culling stats
var culling_stats_timer: float = 0.0
var culling_stats_interval: float = 5.0  # Print stats every 5 seconds

var language_selector = null  # Reference to language selector (includes loading progress)

func _ready():
	# Generate player ULID (represents the current player)
	if UlidManager:
		player_ulid = UlidManager.generate()
		print("Main: Player ULID generated: %s" % UlidManager.to_hex(player_ulid))

	# Show language selector (includes loading progress bar)
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

	# Defer initialization until after all children are ready
	call_deferred("_initialize_game")

func _initialize_game() -> void:
	# Step 1: Map generation (already done in hex_map._ready, update progress)
	if language_selector:
		language_selector.set_map_generation()
		await get_tree().process_frame

	# NOTE: Camera bounds not needed for infinite world
	# Chunks are generated on-demand based on camera position

	# Setup CameraManager with camera reference
	CameraManager.set_camera(camera)

	# Setup hex_map with camera for chunk culling
	hex_map.set_camera(camera)

	# Setup ChunkManager with camera and chunk pool references
	ChunkManager.set_camera(camera)
	ChunkManager.set_chunk_pool(hex_map.chunk_pool)

	# Connect HexMap to ChunkManager for chunk generation
	hex_map.set_chunk_manager(ChunkManager)

	# Setup Cache with tilemap reference for global access
	Cache.set_tile_map(hex_map.tile_map)

	# Reveal starting chunks around camera/cities
	_reveal_starting_chunks()

	# Wait a few frames for initial chunks to generate and render
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	#; TEST
	# Connect hex_map to play_hand for card placement
	play_hand.hex_map = hex_map
	# Connect camera to play_hand for auto-follow
	play_hand.camera = camera
	# NOTE: Camera bounds not needed for infinite world
	# Connect hex_map to tile_info for tile hover display
	tile_info.hex_map = hex_map
	# Connect camera to topbar for CityVote button
	topbar_uiux.camera = camera

	# Connect card signals to control camera panning
	play_hand.card_picked_up.connect(_on_card_picked_up)
	play_hand.card_placed.connect(_on_card_placed)
	play_hand.card_cancelled.connect(_on_card_cancelled)
	#; TEST

	# Step 2: Wait for initial chunks to render
	if language_selector:
		language_selector.set_chunk_rendering()

	# IMPORTANT: Wait for initial chunks to render before spawning entities
	# This prevents race condition where entities spawn before terrain is ready
	print("Main: Waiting for initial chunks to render...")
	await hex_map.initial_chunks_ready
	print("Main: Initial chunks ready! Proceeding with entity spawning...")

	# Step 3: Initialize pathfinding
	if language_selector:
		language_selector.set_pathfinding_init()
		await get_tree().process_frame

	#### TEST ####
	# Initialize Rust pathfinding map cache
	print("Initializing Rust ship pathfinding map cache...")
	get_node("/root/ShipPathfindingBridge").init_map(hex_map)

	print("Initializing Rust NPC pathfinding map cache...")
	get_node("/root/NpcPathfindingBridge").init_map(hex_map)

	# Step 4: Spawn entities
	if language_selector:
		language_selector.set_spawning_entities()
		await get_tree().process_frame

	# Spawn a few test viking ships on water tiles
	_spawn_test_vikings()

	# Spawn test Jezza raptor on land tiles
	_spawn_test_jezza()

	# Spawn test Fantasy Warriors on land tiles
	_spawn_test_fantasy_warriors()

	# Spawn test Kings on land tiles
	_spawn_test_kings()

	# Position camera at a city for a nice starting view
	# DISABLED: Cities don't exist in procedurally generated world yet
	# _position_camera_at_city()

	# Connect to joker consumption signal
	if CardComboBridge:
		CardComboBridge.joker_consumed.connect(_on_joker_consumed)
		print("Main: Connected to joker_consumed signal")

	# Step 5: Complete
	if language_selector:
		language_selector.set_complete()

	# Test toast notification
	Toast.show_toast(I18n.translate("game.welcome"), 5.0)
	await get_tree().create_timer(2.0).timeout
	Toast.show_toast(I18n.translate("game.entities_spawned"), 3.0)

## Show language selector overlay (includes loading progress bar)
func _show_language_selector_overlay() -> void:
	# Load language selector scene (now includes loading progress)
	var selector_scene = load("res://view/hud/i18n/language_selector.tscn")
	if not selector_scene:
		push_error("Main: Failed to load language selector scene!")
		return

	language_selector = selector_scene.instantiate()
	add_child(language_selector)

	# Connect to language_selected signal to start timer
	if language_selector.has_signal("language_selected"):
		language_selector.language_selected.connect(_on_language_selected)

	print("Main: Language selector (with loading progress) displayed")

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

# REMOVED: _calculate_camera_bounds() - Not needed for infinite world
# Camera bounds are unlimited in procedurally generated infinite world

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
	# Update all entities through EntityManager (handles movement timers)
	EntityManager.update_entities(delta, _handle_entity_movement)

	# Update chunk visibility based on camera position (for fog of war and culling)
	ChunkManager.update_visible_chunks()

	# Print culling stats periodically
	culling_stats_timer += delta
	if culling_stats_timer >= culling_stats_interval:
		culling_stats_timer = 0.0
		_print_culling_stats()

func _input(event):
	# Handle right-click to open entity stats panel
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			# Get world position of click
			var world_pos = camera.get_global_mouse_position()

			# Find entity near click position (spatial query with generous radius)
			var entity = EntityManager.find_entity_near_position(world_pos, 32.0)  # 32px search radius

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
	# PROCEDURAL WORLD: Spawn near camera position instead of searching entire map
	var camera_tile = hex_map.tile_renderer.world_to_tile(camera.position)
	var water_tiles: Array = []

	# Search in a 50x50 area around camera (much smaller than 10000x10000!)
	var search_radius = 25
	for x in range(camera_tile.x - search_radius, camera_tile.x + search_radius):
		for y in range(camera_tile.y - search_radius, camera_tile.y + search_radius):
			var tile_coords = Vector2i(x, y)
			# Convert tile coordinates to world position (center of tile)
			var world_pos = hex_map.tile_map.map_to_local(tile_coords)
			# Use WorldGenerator to check terrain (queries procedural generation)
			if hex_map.world_generator and hex_map.world_generator.is_water(world_pos.x, world_pos.y):
				water_tiles.append(tile_coords)

	print("=== VIKING SPAWN ===")
	print("Found ", water_tiles.size(), " water tiles (near camera)")

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

			# Register with EntityManager for tracking and movement
			EntityManager.register_entity(viking, "viking", random_tile)

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

## Generic entity movement handler (called by EntityManager.update_entities)
## @param entity: The entity to move
## @param current_tile: Entity's current tile position
## @param pool_key: Entity type ("viking", "jezza", "fantasywarrior", "king")
## @param registry_entry: Reference to the registry entry (for updating tile)
func _handle_entity_movement(entity: Node, current_tile: Vector2i, pool_key: String, registry_entry: Dictionary) -> void:
	# Skip if still moving
	if entity.is_moving:
		return

	# Handle Vikings (ships) separately - they use different pathfinding
	if pool_key == "viking":
		_handle_viking_movement(entity, current_tile)
		return

	# Land units (jezza, fantasywarrior, king) use NPC pathfinding
	var destination = _find_random_land_destination(current_tile, 3, 8)

	# If no destination found or same as current, skip
	if destination == current_tile:
		return

	# Use Rust NPC pathfinding (async via callback)
	var npc_id = entity.get_instance_id()
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
				entity.follow_path(
					path,
					hex_map.tile_map,
					func():  # On path complete
						# Update occupied tiles
						occupied_tiles[final_destination] = entity
						# Update EntityManager registry
						EntityManager.update_entity_tile(entity, final_destination)
				)
	)

## Handle Viking (ship) movement separately
func _handle_viking_movement(viking: Node, current_tile: Vector2i) -> void:
	# Find a random water destination
	var destination = Pathfinding.find_random_destination(
		current_tile,
		hex_map,
		occupied_tiles,
		viking,
		3,  # min_distance
		10  # max_distance
	)

	# If no destination found, try adjacent tiles
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
			return  # No valid tiles found

	# Use Rust ship pathfinding
	var ship_ulid = viking.ulid
	var pathfinding_bridge = get_node("/root/ShipPathfindingBridge")

	# DEBUG: Check terrain cache for start and goal
	var start_terrain = pathfinding_bridge.debug_check_terrain(current_tile)
	var goal_terrain = pathfinding_bridge.debug_check_terrain(destination)
	var start_walkable = pathfinding_bridge.debug_is_walkable(current_tile)
	var goal_walkable = pathfinding_bridge.debug_is_walkable(destination)
	print("DEBUG: Ship pathfinding from %v to %v" % [current_tile, destination])
	print("  Start terrain: %s (walkable: %s)" % [start_terrain, start_walkable])
	print("  Goal terrain: %s (walkable: %s)" % [goal_terrain, goal_walkable])

	# Update ship position in Rust
	pathfinding_bridge.update_ship_position(ship_ulid, current_tile)

	# Request pathfinding from Rust
	pathfinding_bridge.request_path(
		ship_ulid,
		current_tile,
		destination,
		true,  # avoid_ships
		func(path: Array[Vector2i], success: bool, _cost: float):
			if success and path.size() > 1:
				# Free up current tile
				occupied_tiles.erase(current_tile)

				# Capture final destination
				var final_destination = path[path.size() - 1]

				# Mark ship as MOVING in Rust
				pathfinding_bridge.set_ship_moving(ship_ulid)

				# Follow the full path
				viking.follow_path(
					path,
					hex_map.tile_map,
					func():  # On path complete
						occupied_tiles[final_destination] = viking
						# Update EntityManager registry
						EntityManager.update_entity_tile(viking, final_destination)
						# Mark ship as IDLE in Rust
						pathfinding_bridge.set_ship_idle(ship_ulid)
				)
	)

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

			# No bounds check - infinite world support

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

## Reveal starting chunks around camera and cities
func _reveal_starting_chunks() -> void:
	# Reveal chunks around camera position
	var camera_tile = hex_map.tile_renderer.world_to_tile(camera.position)
	var camera_chunk = MapConfig.tile_to_chunk(camera_tile)

	# Reveal 3x3 area around starting position
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var chunk_coords = Vector2i(camera_chunk.x + dx, camera_chunk.y + dy)
			ChunkManager.reveal_chunk(chunk_coords)

	print("Main: Revealed starting chunks around camera chunk: %v" % camera_chunk)

	# Trigger initial chunk generation
	ChunkManager.update_visible_chunks()

## Position camera at a city on startup for a nice view
func _position_camera_at_city() -> void:
	# Search for a city tile in the tilemap
	var city_tile: Vector2i = Vector2i(-1, -1)

	# Search for city1 or city2 (source IDs 7 or 8)
	for x in range(MapConfig.MAP_WIDTH):
		for y in range(MapConfig.MAP_HEIGHT):
			var tile_coords = Vector2i(x, y)
			var source_id = hex_map.tile_map.get_cell_source_id(0, tile_coords)

			# Found a city!
			if source_id == 7 or source_id == 8:
				city_tile = tile_coords
				break

		if city_tile != Vector2i(-1, -1):
			break

	# If we found a city, pan camera to it
	if city_tile != Vector2i(-1, -1):
		var world_pos = hex_map.tile_map.map_to_local(city_tile)
		print("Main: Positioning camera at city tile %v (world pos: %v)" % [city_tile, world_pos])
		CameraManager.set_position_instant(world_pos)
	else:
		print("Main: No city found, camera remains at default position")

# Camera position clamping - DISABLED for infinite world
# Chunks are generated on-demand, so camera can move freely
func _clamp_camera_position(pos: Vector2) -> Vector2:
	return pos  # No clamping needed for infinite world

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
	# PROCEDURAL WORLD: Spawn near camera position instead of searching entire map
	var camera_tile = hex_map.tile_renderer.world_to_tile(camera.position)
	var land_tiles: Array = []

	# Search in a 50x50 area around camera (much smaller than 10000x10000!)
	var search_radius = 25
	for x in range(camera_tile.x - search_radius, camera_tile.x + search_radius):
		for y in range(camera_tile.y - search_radius, camera_tile.y + search_radius):
			var tile_coords = Vector2i(x, y)
			# Convert tile coordinates to world position (center of tile)
			var world_pos = hex_map.tile_map.map_to_local(tile_coords)
			# Use WorldGenerator to check terrain (queries procedural generation)
			if hex_map.world_generator and not hex_map.world_generator.is_water(world_pos.x, world_pos.y):
				land_tiles.append(tile_coords)

	print("=== JEZZA SPAWN ===")
	print("Found ", land_tiles.size(), " land tiles (near camera)")

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

			# Register with EntityManager for tracking and movement
			EntityManager.register_entity(jezza, "jezza", random_tile)

			# Mark tile as occupied
			occupied_tiles[random_tile] = jezza

			# Store jezza and its current tile (for backward compatibility, can be removed later)
			test_jezzas.append({"entity": jezza, "tile": random_tile})
			print("Spawned Jezza ", i, " at tile ", random_tile, " world pos ", world_pos)
		else:
			print("Failed to acquire Jezza ", i, " from Cluster")

	print("Total Jezza raptors spawned: 3")

func _spawn_test_fantasy_warriors():
	# PROCEDURAL WORLD: Spawn near camera position instead of searching entire map
	var camera_tile = hex_map.tile_renderer.world_to_tile(camera.position)
	var land_tiles: Array = []

	# Search in a 50x50 area around camera (much smaller than 10000x10000!)
	var search_radius = 25
	for x in range(camera_tile.x - search_radius, camera_tile.x + search_radius):
		for y in range(camera_tile.y - search_radius, camera_tile.y + search_radius):
			var tile_coords = Vector2i(x, y)
			# Convert tile coordinates to world position (center of tile)
			var world_pos = hex_map.tile_map.map_to_local(tile_coords)
			# Use WorldGenerator to check terrain (queries procedural generation)
			if hex_map.world_generator and not hex_map.world_generator.is_water(world_pos.x, world_pos.y):
				land_tiles.append(tile_coords)

	print("=== FANTASY WARRIOR SPAWN ===")
	print("Found ", land_tiles.size(), " land tiles (near camera)")

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

			# Register with EntityManager for tracking and movement
			EntityManager.register_entity(warrior, "fantasywarrior", random_tile)

			# Mark tile as occupied
			occupied_tiles[random_tile] = warrior

			# Store warrior and its current tile
			test_fantasy_warriors.append({"entity": warrior, "tile": random_tile})
			print("Spawned Fantasy Warrior ", i, " at tile ", random_tile, " world pos ", world_pos)
		else:
			print("Failed to acquire Fantasy Warrior ", i, " from Cluster")

	print("Total Fantasy Warriors spawned: 3")

func _spawn_test_kings():
	# PROCEDURAL WORLD: Spawn near camera position instead of searching entire map
	var camera_tile = hex_map.tile_renderer.world_to_tile(camera.position)
	var land_tiles: Array = []

	# Search in a 50x50 area around camera (much smaller than 10000x10000!)
	var search_radius = 25
	for x in range(camera_tile.x - search_radius, camera_tile.x + search_radius):
		for y in range(camera_tile.y - search_radius, camera_tile.y + search_radius):
			var tile_coords = Vector2i(x, y)
			# Convert tile coordinates to world position (center of tile)
			var world_pos = hex_map.tile_map.map_to_local(tile_coords)
			# Use WorldGenerator to check terrain (queries procedural generation)
			if hex_map.world_generator and not hex_map.world_generator.is_water(world_pos.x, world_pos.y):
				land_tiles.append(tile_coords)

	print("=== KING SPAWN ===")
	print("Found ", land_tiles.size(), " land tiles (near camera)")

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

			# Register with EntityManager for tracking and movement
			EntityManager.register_entity(king, "king", random_tile)

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

## Print chunk culling statistics
func _print_culling_stats() -> void:
	if not ChunkManager:
		return

	var stats = ChunkManager.get_culling_stats()
	var total_entities = EntityManager.get_registered_entities().size()
	var active = ChunkManager.active_entities_count
	var culled = ChunkManager.culled_entities_count
	var culling_percent = 0.0
	if total_entities > 0:
		culling_percent = (float(culled) / float(total_entities)) * 100.0

	print("=== CHUNK CULLING STATS ===")
	# PROCEDURAL WORLD: Show loaded_chunks instead of total_chunks (infinite world has no total)
	print("Visible Chunks: %d / %d loaded (render_radius=%d)" % [stats["visible_chunks"], stats["loaded_chunks"], stats["render_radius"]])
	print("Total Entities: %d" % total_entities)
	print("Active Entities: %d (%.1f%%)" % [active, 100.0 - culling_percent])
	print("Culled Entities: %d (%.1f%%)" % [culled, culling_percent])
	print("Culling Enabled: %s" % ("YES" if stats["culling_enabled"] else "NO"))
	print("============================")
