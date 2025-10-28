extends Node

# Bridge between GDScript and Rust pathfinding system
# Manages ship pathfinding requests and results

var pathfinding_bridge: Node = null
var pending_requests: Dictionary = {}  # ship_id -> callback

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

	print("ShipPathfindingBridge: Ready! Workers started.")

func _process(delta: float) -> void:
	# Incremental map sync
	sync_timer += delta
	if sync_timer >= sync_interval and dirty_tiles.size() > 0:
		sync_dirty_tiles()
		sync_timer = 0.0

func _on_path_found(ship_id: int, path: Array, success: bool, cost: float) -> void:
	# Call callback if registered
	if pending_requests.has(ship_id):
		var callback = pending_requests[ship_id]
		pending_requests.erase(ship_id)

		# Convert path to Vector2i array
		var path_coords: Array[Vector2i] = []
		for coord_dict in path:
			path_coords.append(Vector2i(coord_dict["q"], coord_dict["r"]))

		# Call the callback
		callback.call(path_coords, success, cost)

# === PUBLIC API ===

## Initialize map cache (call once at startup)
func init_map(hex_map: Node) -> void:
	if not pathfinding_bridge:
		push_error("ShipPathfindingBridge: Not initialized!")
		return

	var tiles: Array[Dictionary] = []

	# Get all tiles from hex map
	var tile_map = hex_map.tile_map
	for x in range(50):  # Assuming 50x50 map
		for y in range(50):
			var tile_coords = Vector2i(x, y)
			var source_id = tile_map.get_cell_source_id(0, tile_coords)

			# Convert to axial hex coords and tile type
			var tile_dict = Dictionary()
			tile_dict["q"] = x
			tile_dict["r"] = y

			# Map source_id to TileType (0=Water, 1=Land, 2=Obstacle)
			if source_id == 4:  # Water
				tile_dict["type"] = 0
			else:  # Land
				tile_dict["type"] = 1

			tiles.append(tile_dict)

	pathfinding_bridge.init_map(tiles)

## Check if ship can accept a path request (not already moving)
func can_ship_request_path(ship_id: int) -> bool:
	if not pathfinding_bridge:
		return false
	return pathfinding_bridge.can_ship_request_path(ship_id)

## Set ship state to MOVING (call when ship starts following path)
func set_ship_moving(ship_id: int) -> void:
	if pathfinding_bridge:
		pathfinding_bridge.set_ship_moving(ship_id)

## Set ship state to IDLE (call when ship stops moving)
func set_ship_idle(ship_id: int) -> void:
	if pathfinding_bridge:
		pathfinding_bridge.set_ship_idle(ship_id)

## Request pathfinding (async, callback receives result)
func request_path(ship_id: int, start: Vector2i, goal: Vector2i, avoid_ships: bool, callback: Callable) -> void:
	if not pathfinding_bridge:
		push_error("ShipPathfindingBridge: Not initialized!")
		return

	# Check if ship can accept request
	if not can_ship_request_path(ship_id):
		return

	# Register callback
	pending_requests[ship_id] = callback

	# Send request to Rust (Rust will mark ship as PATHFINDING)
	pathfinding_bridge.request_path(ship_id, start.x, start.y, goal.x, goal.y, avoid_ships)

## Update ship position (call when ship moves)
func update_ship_position(ship_id: int, position: Vector2i) -> void:
	if pathfinding_bridge:
		pathfinding_bridge.update_ship_position(ship_id, position.x, position.y)

## Remove ship (call when ship is destroyed)
func remove_ship(ship_id: int) -> void:
	if pathfinding_bridge:
		pathfinding_bridge.remove_ship(ship_id)
		pending_requests.erase(ship_id)

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
		print("ShipPathfindingBridge: Workers stopped.")
