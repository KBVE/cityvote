extends Node

# Bridge between GDScript and Rust pathfinding system
# Manages ship pathfinding requests and results

var pathfinding_bridge: Node = null
var pending_requests: Dictionary = {}  # ship_ulid_hex -> callback (using hex string as key for Dictionary)

# Map sync settings
var sync_interval: float = 5.0  # Sync dirty tiles every 5 seconds
var sync_timer: float = 0.0
var dirty_tiles: Array[Dictionary] = []

func _ready() -> void:
	# Create the Rust pathfinding bridge
	pathfinding_bridge = ClassDB.instantiate("ShipPathfindingBridge")

	if pathfinding_bridge == null:
		push_error("ShipPathfindingBridge: Failed to instantiate from Rust!")
		return

	add_child(pathfinding_bridge)

	# Connect signal
	pathfinding_bridge.connect("path_found", _on_path_found)

	# Start worker threads (2 threads for pathfinding)
	pathfinding_bridge.start_workers(2)

func _process(delta: float) -> void:
	# Incremental map sync
	sync_timer += delta
	if sync_timer >= sync_interval and dirty_tiles.size() > 0:
		sync_dirty_tiles()
		sync_timer = 0.0

func _on_path_found(ship_ulid: PackedByteArray, path: Array, success: bool, cost: float) -> void:
	# Convert ULID to hex for Dictionary lookup
	var ulid_key = UlidManager.to_hex(ship_ulid)

	# Call callback if registered
	if pending_requests.has(ulid_key):
		var callback = pending_requests[ulid_key]
		pending_requests.erase(ulid_key)

		# Convert path to Vector2i array
		var path_coords: Array[Vector2i] = []
		for coord_dict in path:
			path_coords.append(Vector2i(coord_dict["q"], coord_dict["r"]))

		# Call the callback
		callback.call(path_coords, success, cost)

# === PUBLIC API ===

## Initialize map cache (call once at startup)
## PROCEDURAL WORLD: No initialization needed - chunks are loaded on-demand
func init_map(hex_map: Node) -> void:
	if not pathfinding_bridge:
		push_error("ShipPathfindingBridge: Not initialized!")
		return

	# PROCEDURAL WORLD: Skip full map initialization
	# Terrain cache is populated incrementally as chunks are generated
	# The WorldGenerator provides terrain data on-demand
	print("ShipPathfindingBridge: init_map called - using on-demand chunk loading (infinite world)")

	# Initialize with empty array - terrain will be loaded as chunks are requested
	var tiles: Array[Dictionary] = []
	pathfinding_bridge.init_map(tiles)
	print("ShipPathfindingBridge: Map initialized for infinite world (0 tiles pre-loaded, chunks loaded on-demand)")

## Check if ship can accept a path request (not already moving)
func can_ship_request_path(ship_ulid: PackedByteArray) -> bool:
	if not pathfinding_bridge:
		return false
	return pathfinding_bridge.can_ship_request_path(ship_ulid)

## Set ship state to MOVING (call when ship starts following path)
func set_ship_moving(ship_ulid: PackedByteArray) -> void:
	if pathfinding_bridge:
		pathfinding_bridge.set_ship_moving(ship_ulid)

## Set ship state to IDLE (call when ship stops moving)
func set_ship_idle(ship_ulid: PackedByteArray) -> void:
	if pathfinding_bridge:
		pathfinding_bridge.set_ship_idle(ship_ulid)

## Request pathfinding (async, callback receives result)
func request_path(ship_ulid: PackedByteArray, start: Vector2i, goal: Vector2i, avoid_ships: bool, callback: Callable) -> void:
	if not pathfinding_bridge:
		push_error("ShipPathfindingBridge: Not initialized!")
		return

	# Check if ship can accept request
	if not can_ship_request_path(ship_ulid):
		return

	# Register callback (using hex string as Dictionary key)
	var ulid_key = UlidManager.to_hex(ship_ulid)
	pending_requests[ulid_key] = callback

	# Send request to Rust (Rust will mark ship as PATHFINDING)
	pathfinding_bridge.request_path(ship_ulid, start.x, start.y, goal.x, goal.y, avoid_ships)

## Update ship position (call when ship moves)
func update_ship_position(ship_ulid: PackedByteArray, position: Vector2i) -> void:
	if pathfinding_bridge:
		pathfinding_bridge.update_ship_position(ship_ulid, position.x, position.y)

## Remove ship (call when ship is destroyed)
func remove_ship(ship_ulid: PackedByteArray) -> void:
	if pathfinding_bridge:
		var ulid_key = UlidManager.to_hex(ship_ulid)
		pathfinding_bridge.remove_ship(ship_ulid)
		pending_requests.erase(ulid_key)

## Load a chunk into the pathfinding terrain cache (for procedural world)
func load_chunk(chunk_coords: Vector2i, tile_data: Array) -> void:
	if not pathfinding_bridge:
		return

	# Convert chunk tile data to pathfinding format
	var tiles: Array[Dictionary] = []
	for tile in tile_data:
		var tile_dict = Dictionary()
		# tile_data contains: {tile_index: int, x: int, y: int}
		# tile_index matches atlas: 0-3,5-6 = grassland variants, 4 = water
		tile_dict["q"] = tile["x"]
		tile_dict["r"] = tile["y"]

		# Map tile_index to TileType (0=Water, 1=Land, 2=Obstacle)
		if tile["tile_index"] == 4:
			tile_dict["type"] = 0  # Water
		else:
			tile_dict["type"] = 1  # Land (grasslands, etc.)

		tiles.append(tile_dict)

	# Update pathfinding cache with chunk data
	if tiles.size() > 0:
		pathfinding_bridge.update_tiles(tiles)
		print("ShipPathfindingBridge: Loaded chunk %v (%d tiles) into pathfinding cache" % [chunk_coords, tiles.size()])

## Mark tile as dirty (will sync on next interval)
func mark_tile_dirty(coord: Vector2i, tile_type: int) -> void:
	var tile_dict = Dictionary()
	tile_dict["q"] = coord.x
	tile_dict["r"] = coord.y
	tile_dict["type"] = tile_type
	dirty_tiles.append(tile_dict)

## Force sync dirty tiles now
func sync_dirty_tiles() -> void:
	if dirty_tiles.size() == 0:
		return

	if pathfinding_bridge:
		pathfinding_bridge.update_tiles(dirty_tiles)
		dirty_tiles.clear()

## Get statistics
func get_stats() -> Dictionary:
	if pathfinding_bridge:
		return pathfinding_bridge.get_stats()
	return {}

func _exit_tree() -> void:
	if pathfinding_bridge:
		pathfinding_bridge.stop_workers()
