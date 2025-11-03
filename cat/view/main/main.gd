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

# Skull Wizard NPC testing
var test_skull_wizards: Array = []

# Fireworm NPC testing
var test_fireworms: Array = []

# Chunk culling stats
var culling_stats_timer: float = 0.0
var culling_stats_interval: float = 5.0  # Print stats every 5 seconds

func _ready():
	# Set Cache references for efficient access
	Cache.set_main_scene(self)
	Cache.set_ui_reference("topbar", topbar_uiux)
	Cache.set_ui_reference("tile_info", tile_info)
	Cache.set_ui_reference("entity_stats_panel", entity_stats_panel)

	# Generate player ULID (represents the current player)
	if UlidManager:
		player_ulid = UlidManager.generate()
	else:
		push_error("Main: UlidManager not found!")

	# Note: Language/seed selection now happens in title.tscn
	# World seed already set in MapConfig by title.gd

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
	print("DEBUG: Main._initialize_game() starting...")

	# Step 1: Map generation (already done in hex_map._ready)
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
	# IMPORTANT: Wait for initial chunks to render before spawning entities
	# This prevents race condition where entities spawn before terrain is ready
	if not hex_map.initial_chunks_loaded:
		print("DEBUG: Waiting for initial_chunks_ready...")
		await hex_map.initial_chunks_ready
		print("DEBUG: initial_chunks_ready received!")
	else:
		print("DEBUG: initial_chunks already loaded, skipping wait")

	# Step 3: Initialize pathfinding
	await get_tree().process_frame

	#### TEST ####
	# NOTE: Terrain cache is populated incrementally via load_chunk() as chunks are generated
	# No need to call init_map() - chunks auto-populate the cache in hex.gd:199

	# Step 4: Spawn entities
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
	else:
		push_error("Main: CardComboBridge not found!")

	# Step 5: Complete - Start game timer
	if GameTimer:
		GameTimer.start_timer()
	else:
		push_error("Main: GameTimer not found!")

	# Test toast notification
	Toast.show_toast(I18n.translate("game.welcome"), 5.0)
	await get_tree().create_timer(2.0).timeout
	Toast.show_toast(I18n.translate("game.entities_spawned"), 3.0)

# === Card Signal Handlers ===
func _on_card_picked_up() -> void:
	# Keep manual panning enabled - auto-follow and manual work together
	pass

func _on_card_placed() -> void:
	pass

func _on_card_cancelled() -> void:
	pass

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

	# Print culling stats periodically (disabled)
	# culling_stats_timer += delta
	# if culling_stats_timer >= culling_stats_interval:
	# 	culling_stats_timer = 0.0
	# 	_print_culling_stats()

func _input(event):
	# Handle right-click to open entity stats panel
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			# Get world position of click
			var world_pos = camera.get_global_mouse_position()

			# Find entity near click position (spatial query with generous radius)
			var entity = EntityManager.find_entity_near_position(world_pos, 32.0)  # 32px search radius

			if entity:
				# Get entity name (translated)
				var entity_name = "Unknown"
				if entity is Jezza:
					entity_name = I18n.translate("entity.jezza_raptor")
				elif entity is FantasyWarrior:
					entity_name = I18n.translate("entity.fantasy_warrior.name")
				elif entity is King:
					entity_name = I18n.translate("entity.king.name")
				elif entity is NPC:
					# Check terrain type for water entities (vikings/ships)
					if "terrain_type" in entity and entity.terrain_type == NPC.TerrainType.WATER:
						entity_name = I18n.translate("entity.viking.name")
					else:
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
	# Get spawn position near camera
	var spawn_near = hex_map.tile_renderer.world_to_tile(camera.position)

	# Spawn 10 vikings using EntityManager (which uses EntitySpawnBridge internally)
	# NOTE: Vikings spawn on water near camera position (where chunks are loaded)
	var count = EntityManager.spawn_multiple({
		"pool_key": "viking",
		"count": 10,
		"tile_type": EntityManager.TileType.WATER,
		"hex_map": hex_map,
		"tile_map": hex_map.tile_map,
		"occupied_tiles": occupied_tiles,
		"storage_array": test_vikings,
		"player_ulid": player_ulid,
		"near_pos": spawn_near,  # Spawn near camera where chunks are loaded
		"entity_name": "Viking",
		"post_spawn_callback": _apply_wave_shader_to_viking
	})

## Generic entity movement handler (called by EntityManager.update_entities)
## @param entity: The entity to move
## @param current_tile: Entity's current tile position
## @param pool_key: Entity type ("viking", "jezza", "fantasywarrior", "king")
## @param registry_entry: Reference to the registry entry (for updating tile)
func _handle_entity_movement(entity: Node, current_tile: Vector2i, pool_key: String, registry_entry: Dictionary) -> void:
	# Defensive: Validate entity exists
	if not entity or not is_instance_valid(entity):
		push_error("_handle_entity_movement: Invalid entity for pool_key=%s" % pool_key)
		return

	# Skip if entity is not idle (check state flags instead of redundant variables)
	# State.MOVING = 0b0010, State.PATHFINDING = 0b0100, State.BLOCKED = 0b1000
	const MOVING = 0b0010
	const PATHFINDING = 0b0100
	const BLOCKED = 0b1000

	# Entity must be idle (not moving, pathfinding, or blocked)
	if (entity.current_state & (MOVING | PATHFINDING | BLOCKED)) != 0:
		return

	# Also check if entity has a path it's following
	if entity.current_path.size() > 0:
		return

	# Defensive: Validate entity has required properties
	if not "ulid" in entity:
		push_error("_handle_entity_movement: Entity %s missing 'ulid' property!" % pool_key)
		return

	if not "terrain_type" in entity:
		push_error("_handle_entity_movement: Entity %s missing 'terrain_type' property!" % pool_key)
		return

	# Validate entity has ULID
	if entity.ulid.is_empty():
		push_error("_handle_entity_movement: Entity %s has empty ULID!" % pool_key)
		return

	# Defensive: Get pathfinding bridge with null check
	var pathfinding_bridge = get_node_or_null("/root/UnifiedPathfindingBridge")
	if not pathfinding_bridge:
		push_error("_handle_entity_movement: UnifiedPathfindingBridge not found!")
		return

	# Unified pathfinding for ALL entity types (water and land)
	# Determine random destination distance based on entity type
	var min_distance = 2 if pool_key == "viking" else 3
	var max_distance = 5 if pool_key == "viking" else 8

	# Find random destination using unified pathfinding (works for both water and land)
	var destination = pathfinding_bridge.find_random_destination(
		entity.ulid,
		entity.terrain_type,
		current_tile,
		min_distance,
		max_distance
	)

	# If no destination found, return silently
	if destination == current_tile:
		return

	# Free up current tile immediately
	occupied_tiles.erase(current_tile)

	# Defensive: Validate entity has request_pathfinding method
	if not entity.has_method("request_pathfinding"):
		push_error("_handle_entity_movement: Entity %s missing 'request_pathfinding' method!" % pool_key)
		occupied_tiles[current_tile] = entity  # Put it back
		return

	# Use unified entity pathfinding (handles both water and land entities)
	entity.request_pathfinding(
		destination,
		hex_map.tile_map,
		func(path: Array[Vector2i], success: bool):
			# Callback when path is complete
			if success and path.size() > 0:
				var final_destination = path[path.size() - 1]

				# CRITICAL: Validate final destination terrain matches entity terrain_type
				if pathfinding_bridge and not pathfinding_bridge.is_tile_walkable(entity.terrain_type, final_destination):
					push_error("TERRAIN MISMATCH: %s (terrain_type=%d) ended at %s which is NOT walkable! Keeping at %s" %
						[pool_key, entity.terrain_type, final_destination, current_tile])
					occupied_tiles[current_tile] = entity  # Keep at current tile
					return

				# Update occupied tiles
				occupied_tiles[final_destination] = entity
				# Update EntityManager registry
				EntityManager.update_entity_tile(entity, final_destination)
			else:
				# Pathfinding failed - entity stays at current tile
				occupied_tiles[current_tile] = entity
	)

# NOTE: All old manual movement functions removed (_handle_viking_movement, _move_test_vikings, etc.)
# EntityManager now handles movement for ALL entity types through unified _handle_entity_movement()

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
		CameraManager.set_position_instant(world_pos)

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
	print("DEBUG: _spawn_test_jezza() called - using Rust-authoritative EntityManager")

	# Spawn 3 Jezzas using EntityManager (which uses EntitySpawnBridge internally)
	var count = EntityManager.spawn_multiple({
		"pool_key": "jezza",
		"count": 3,
		"tile_type": EntityManager.TileType.LAND,
		"hex_map": hex_map,
		"tile_map": hex_map.tile_map,
		"occupied_tiles": occupied_tiles,
		"storage_array": test_jezzas,
		"player_ulid": player_ulid,
		"near_pos": hex_map.tile_renderer.world_to_tile(camera.position),
		"entity_name": "Jezza"
	})

	print("DEBUG: Spawned %d Jezzas" % count)

func _spawn_test_fantasy_warriors():
	print("DEBUG: _spawn_test_fantasy_warriors() called - using Rust-authoritative EntityManager")

	# Spawn 3 Fantasy Warriors using EntityManager (which uses EntitySpawnBridge internally)
	var count = EntityManager.spawn_multiple({
		"pool_key": "fantasywarrior",
		"count": 3,
		"tile_type": EntityManager.TileType.LAND,
		"hex_map": hex_map,
		"tile_map": hex_map.tile_map,
		"occupied_tiles": occupied_tiles,
		"storage_array": test_fantasy_warriors,
		"player_ulid": player_ulid,
		"near_pos": hex_map.tile_renderer.world_to_tile(camera.position),
		"entity_name": "Fantasy Warrior"
	})

	print("DEBUG: Spawned %d Fantasy Warriors" % count)

func _spawn_test_kings():
	print("DEBUG: _spawn_test_kings() called - using Rust-authoritative EntityManager")

	# Spawn 3 Kings using EntityManager (which uses EntitySpawnBridge internally)
	var count = EntityManager.spawn_multiple({
		"pool_key": "king",
		"count": 3,
		"tile_type": EntityManager.TileType.LAND,
		"hex_map": hex_map,
		"tile_map": hex_map.tile_map,
		"occupied_tiles": occupied_tiles,
		"storage_array": test_kings,
		"player_ulid": player_ulid,
		"near_pos": hex_map.tile_renderer.world_to_tile(camera.position),
		"entity_name": "King"
	})

	print("DEBUG: Spawned %d Kings" % count)

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
		"BARON":
			# Spawn 3 kings per card (count × 3)
			var total_kings = count * 3
			EntityManager.spawn_multiple({
				"pool_key": "king",
				"count": total_kings,
				"tile_type": EntityManager.TileType.LAND,
				"hex_map": hex_map,
				"tile_map": hex_map.tile_map,
				"occupied_tiles": occupied_tiles,
				"storage_array": test_kings,
				"player_ulid": player_ulid,
				"near_pos": card_pos,
				"entity_name": "King"
			})
			Toast.show_toast("Spawned %d Kings!" % total_kings, 3.0)
		"SKULL_WIZARD":
			# Spawn 3 skull wizards per card (count × 3)
			var total_wizards = count * 3
			EntityManager.spawn_multiple({
				"pool_key": "skullwizard",
				"count": total_wizards,
				"tile_type": EntityManager.TileType.LAND,
				"hex_map": hex_map,
				"tile_map": hex_map.tile_map,
				"occupied_tiles": occupied_tiles,
				"storage_array": test_skull_wizards,
				"player_ulid": player_ulid,
				"near_pos": card_pos,
				"entity_name": "Skull Wizard"
			})
			Toast.show_toast("Spawned %d Skull Wizards!" % total_wizards, 3.0)
		"WARRIOR":
			# Spawn 3 fantasy warriors per card (count × 3)
			var total_warriors = count * 3
			EntityManager.spawn_multiple({
				"pool_key": "fantasywarrior",
				"count": total_warriors,
				"tile_type": EntityManager.TileType.LAND,
				"hex_map": hex_map,
				"tile_map": hex_map.tile_map,
				"occupied_tiles": occupied_tiles,
				"storage_array": test_fantasy_warriors,
				"player_ulid": player_ulid,
				"near_pos": card_pos,
				"entity_name": "Fantasy Warrior"
			})
			Toast.show_toast("Spawned %d Fantasy Warriors!" % total_warriors, 3.0)
		"FIREWORM":
			# Spawn 3 fireworms per card (count × 3)
			var total_fireworms = count * 3
			EntityManager.spawn_multiple({
				"pool_key": "fireworm",
				"count": total_fireworms,
				"tile_type": EntityManager.TileType.LAND,
				"hex_map": hex_map,
				"tile_map": hex_map.tile_map,
				"occupied_tiles": occupied_tiles,
				"storage_array": test_fireworms,
				"player_ulid": player_ulid,
				"near_pos": card_pos,
				"entity_name": "Fireworm"
			})
			Toast.show_toast("Spawned %d Fireworms!" % total_fireworms, 3.0)
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

	# Chunk culling statistics available via ChunkManager.get_culling_stats()
	# Removed debug prints - use profiler or debug overlay if needed
