extends Node

# Unified pathfinding bridge that calls Rust pathfinding systems directly
# Routes water entities to ShipPathfindingBridge (Rust)
# Routes land entities to NpcPathfindingSystem (Rust)

# Terrain type enum (matches NPC.TerrainType)
enum TerrainType {
	LAND = 0b01,
	WATER = 0b10,
}

# Direct references to Rust pathfinding systems
var ship_pathfinding: Node = null  # ShipPathfindingBridge (Rust)
var npc_pathfinding: Node = null   # NpcPathfindingSystem (Rust)

# Pending NPC pathfinding requests (since NPC system doesn't use signals)
var pending_npc_requests: Dictionary = {}  # ulid_hex -> {ulid: PackedByteArray, callback: Callable}

# Map sync settings for ships
var sync_interval: float = 5.0
var sync_timer: float = 0.0
var dirty_tiles: Array[Dictionary] = []

func _ready() -> void:
	# Instantiate Rust pathfinding systems directly
	call_deferred("_initialize_bridges")

func _initialize_bridges() -> void:
	# Instantiate ShipPathfindingBridge from Rust
	ship_pathfinding = ClassDB.instantiate("ShipPathfindingBridge")
	if not ship_pathfinding:
		push_error("UnifiedPathfindingBridge: Failed to instantiate ShipPathfindingBridge from Rust!")
	else:
		add_child(ship_pathfinding)
		# Connect signal for ship pathfinding results
		ship_pathfinding.connect("path_found", _on_ship_path_found)
		# Start worker threads
		ship_pathfinding.start_workers(2)

	# Instantiate NpcPathfindingSystem from Rust
	npc_pathfinding = ClassDB.instantiate("NpcPathfindingSystem")
	if not npc_pathfinding:
		push_error("UnifiedPathfindingBridge: Failed to instantiate NpcPathfindingSystem from Rust!")
	else:
		add_child(npc_pathfinding)

func _process(delta: float) -> void:
	# Incremental map sync for ships
	sync_timer += delta
	if sync_timer >= sync_interval and dirty_tiles.size() > 0:
		_sync_dirty_tiles()
		sync_timer = 0.0

	# Poll for NPC pathfinding results
	_check_npc_pathfinding_results()

func _on_ship_path_found(ship_ulid: PackedByteArray, path: Array, success: bool, cost: float) -> void:
	# This is handled by ship_pathfinding's pending_requests directly
	pass

func _check_npc_pathfinding_results() -> void:
	# Check for completed NPC pathfinding results
	for ulid_hex in pending_npc_requests.keys():
		var request_data = pending_npc_requests[ulid_hex]
		var npc_ulid: PackedByteArray = request_data["ulid"]

		if npc_pathfinding.is_path_ready(npc_ulid):
			var callback = request_data["callback"]
			pending_npc_requests.erase(ulid_hex)

			# Get path from Rust
			var path_array = npc_pathfinding.get_npc_path(npc_ulid)

			# Convert to Array[Vector2i]
			var path_coords: Array[Vector2i] = []
			for coord in path_array:
				path_coords.append(Vector2i(coord.x, coord.y))

			# Call callback
			var success = path_coords.size() > 0
			callback.call(path_coords, success, 0.0)

# === PUBLIC API ===

## Initialize map cache (call once at startup)
## PROCEDURAL WORLD: No initialization needed - chunks are loaded on-demand
func init_map(hex_map: Node) -> void:
	if ship_pathfinding:
		var tiles: Array[Dictionary] = []
		ship_pathfinding.init_map(tiles)
	else:
		push_error("UnifiedPathfindingBridge: Ship pathfinding not found!")

	# NPC pathfinding doesn't need explicit initialization
	if not npc_pathfinding:
		push_error("UnifiedPathfindingBridge: NPC pathfinding not found!")

## Load a chunk into pathfinding terrain cache (for procedural world)
func load_chunk(chunk_coords: Vector2i, tile_data: Array) -> void:
	# Calculate chunk's top-left tile coordinates
	var chunk_start = MapConfig.chunk_to_tile(chunk_coords)

	# Load into ship pathfinding (water entities)
	if ship_pathfinding:
		var ship_tiles: Array[Dictionary] = []
		for tile in tile_data:
			var tile_dict = Dictionary()
			var world_x = chunk_start.x + tile["x"]
			var world_y = chunk_start.y + tile["y"]
			tile_dict["q"] = world_x
			tile_dict["r"] = world_y
			# For ships: water is walkable, land is not
			if tile["tile_index"] == 4:
				tile_dict["type"] = "water"
			else:
				tile_dict["type"] = "land"
			ship_tiles.append(tile_dict)

		if ship_tiles.size() > 0:
			ship_pathfinding.update_tiles(ship_tiles)

	# Load into NPC pathfinding (land entities)
	if npc_pathfinding:
		for tile in tile_data:
			var world_x = chunk_start.x + tile["x"]
			var world_y = chunk_start.y + tile["y"]
			var tile_index = tile["tile_index"]
			# For NPCs: land is walkable, water is not
			if tile_index == 4:
				npc_pathfinding.set_tile(world_x, world_y, "water")
			else:
				npc_pathfinding.set_tile(world_x, world_y, "land")

## Request pathfinding with unified interface
## entity_id: PackedByteArray (ULID) for all entities
## terrain_type: TerrainType.WATER or TerrainType.LAND
## callback: Callable(path: Array[Vector2i], success: bool, cost: float = 0.0)
##           Note: cost is only provided for water entities
func request_path(
	entity_id: PackedByteArray,  # ULID for all entities
	terrain_type: int,
	start: Vector2i,
	goal: Vector2i,
	callback: Callable
) -> void:
	if terrain_type == TerrainType.WATER:
		_request_water_path(entity_id, start, goal, callback)
	else:
		_request_land_path(entity_id, start, goal, callback)

## Update entity position (for pathfinding state management)
func update_entity_position(entity_id, terrain_type: int, position: Vector2i) -> void:
	if terrain_type == TerrainType.WATER:
		if ship_pathfinding:
			ship_pathfinding.update_ship_position(entity_id, position.x, position.y)
	# Land entities don't track position in pathfinding system

## Remove entity from pathfinding system
func remove_entity(entity_id: PackedByteArray, terrain_type: int) -> void:
	if terrain_type == TerrainType.WATER:
		if ship_pathfinding:
			ship_pathfinding.remove_ship(entity_id)
	else:
		if npc_pathfinding:
			# Cancel any pending pathfinding request for this ULID
			var ulid_hex = UlidManager.to_hex(entity_id)
			pending_npc_requests.erase(ulid_hex)

## Set entity state (water entities only)
func set_entity_moving(entity_id: PackedByteArray, terrain_type: int) -> void:
	if terrain_type == TerrainType.WATER and ship_pathfinding:
		ship_pathfinding.set_ship_moving(entity_id)

func set_entity_idle(entity_id: PackedByteArray, terrain_type: int) -> void:
	if terrain_type == TerrainType.WATER and ship_pathfinding:
		ship_pathfinding.set_ship_idle(entity_id)

## Check if entity can request path (water entities only)
func can_entity_request_path(entity_id: PackedByteArray, terrain_type: int) -> bool:
	if terrain_type == TerrainType.WATER and ship_pathfinding:
		return ship_pathfinding.can_ship_request_path(entity_id)
	return true  # Land entities can always request

## Mark tile as dirty (water entities only - uses incremental sync)
func mark_tile_dirty(coord: Vector2i, tile_type: String) -> void:
	var tile_dict = Dictionary()
	tile_dict["q"] = coord.x
	tile_dict["r"] = coord.y
	tile_dict["type"] = tile_type
	dirty_tiles.append(tile_dict)

## Force sync dirty tiles now
func _sync_dirty_tiles() -> void:
	if dirty_tiles.size() == 0:
		return

	if ship_pathfinding:
		ship_pathfinding.update_tiles(dirty_tiles)
		dirty_tiles.clear()

## Get statistics
func get_stats() -> Dictionary:
	var stats = {}
	if ship_pathfinding:
		stats["water"] = ship_pathfinding.get_stats()
	return stats

## Clear all pathfinding data
func clear_all() -> void:
	if npc_pathfinding:
		npc_pathfinding.clear_all()
	pending_npc_requests.clear()

## Find a random reachable destination for an entity
## Returns Vector2i destination, or start if no valid destination found
func find_random_destination(
	entity_id: PackedByteArray,
	terrain_type: int,
	start: Vector2i,
	min_distance: int,
	max_distance: int
) -> Vector2i:
	if terrain_type == TerrainType.WATER and ship_pathfinding:
		# Water entities - use ship pathfinding
		var result_dict = ship_pathfinding.find_random_destination(
			entity_id,
			start.x,
			start.y,
			min_distance,
			max_distance
		)
		return Vector2i(result_dict["q"], result_dict["r"])
	elif terrain_type == TerrainType.LAND and npc_pathfinding:
		# Land entities - use NPC pathfinding
		var result_dict = npc_pathfinding.find_random_destination(
			start.x,
			start.y,
			min_distance,
			max_distance
		)
		return Vector2i(result_dict["q"], result_dict["r"])
	else:
		# Fallback: return start if pathfinding system not available
		return start

func _exit_tree() -> void:
	if ship_pathfinding:
		ship_pathfinding.stop_workers()

# === INTERNAL ROUTING ===

func _request_water_path(ship_ulid: PackedByteArray, start: Vector2i, goal: Vector2i, callback: Callable) -> void:
	if not ship_pathfinding:
		push_error("UnifiedPathfindingBridge: ShipPathfindingBridge not available!")
		callback.call([], false, 0.0)
		return

	# Register ship position if this is the first pathfinding request
	# This ensures ship exists in SHIP_DATA for state tracking
	ship_pathfinding.update_ship_position(ship_ulid, start.x, start.y)

	# Check if ship can accept request
	if not ship_pathfinding.can_ship_request_path(ship_ulid):
		return

	# Register callback (using hex string as Dictionary key)
	var ulid_key = UlidManager.to_hex(ship_ulid)
	var pending_requests = {}  # Local dict for ship requests
	pending_requests[ulid_key] = callback

	# Store callback with custom signal handler
	var signal_handler = func(result_ulid: PackedByteArray, path: Array, success: bool, cost: float):
		var result_key = UlidManager.to_hex(result_ulid)
		if result_key == ulid_key:
			print("UnifiedPathfindingBridge: Ship %s path result received (success=%s, waypoints=%d)" % [result_key, success, path.size()])
			# Convert path to Vector2i array
			var path_coords: Array[Vector2i] = []
			for coord_dict in path:
				path_coords.append(Vector2i(coord_dict["q"], coord_dict["r"]))
			callback.call(path_coords, success, cost)

	# Connect one-shot signal
	ship_pathfinding.path_found.connect(signal_handler, CONNECT_ONE_SHOT)

	# Ship pathfinding provides cost parameter
	# FIXME: Disable ship avoidance for now - with many ships in close proximity,
	# they block each other's paths. Need smarter collision avoidance (e.g., only avoid
	# stationary ships, or use dynamic obstacle avoidance during movement)
	var avoid_ships = false
	ship_pathfinding.request_path(ship_ulid, start.x, start.y, goal.x, goal.y, avoid_ships)

func _request_land_path(npc_ulid: PackedByteArray, start: Vector2i, goal: Vector2i, callback: Callable) -> void:
	if not npc_pathfinding:
		push_error("UnifiedPathfindingBridge: NpcPathfindingBridge not available!")
		callback.call([], false, 0.0)
		return

	# Use hex string as Dictionary key (since PackedByteArray can't be a key)
	var ulid_hex = UlidManager.to_hex(npc_ulid)

	# Don't allow duplicate requests for same NPC
	if pending_npc_requests.has(ulid_hex):
		push_warning("UnifiedPathfindingBridge: NPC %s already has pending path request" % ulid_hex)
		return

	# Register callback with ULID
	pending_npc_requests[ulid_hex] = {
		"ulid": npc_ulid,
		"callback": callback
	}

	# Send request to Rust
	npc_pathfinding.request_path(npc_ulid, start.x, start.y, goal.x, goal.y)
