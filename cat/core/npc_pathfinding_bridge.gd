extends Node

# Bridge between GDScript and Rust NPC pathfinding system
# Manages ground NPC pathfinding requests and results

var pathfinding_system: Node = null
var pending_requests: Dictionary = {}  # npc_id -> callback

func _ready() -> void:
	# Create the Rust NPC pathfinding system
	pathfinding_system = ClassDB.instantiate("NpcPathfindingSystem")

	if pathfinding_system == null:
		push_error("NpcPathfindingBridge: Failed to instantiate NpcPathfindingSystem from Rust!")
		return

	add_child(pathfinding_system)

func _process(_delta: float) -> void:
	# Check for completed pathfinding results
	for npc_id in pending_requests.keys():
		if pathfinding_system.is_path_ready(npc_id):
			var callback = pending_requests[npc_id]
			pending_requests.erase(npc_id)

			# Get path from Rust
			var path_array = pathfinding_system.get_npc_path(npc_id)

			# Convert to Array[Vector2i]
			var path_coords: Array[Vector2i] = []
			for coord in path_array:
				path_coords.append(Vector2i(coord.x, coord.y))

			# Call callback
			var success = path_coords.size() > 0
			callback.call(path_coords, success)

# === PUBLIC API ===

## Initialize map cache (call once at startup)
func init_map(hex_map: Node) -> void:
	if not pathfinding_system:
		push_error("NpcPathfindingBridge: Not initialized!")
		return

	# Read directly from map_data array (memory) instead of TileMap (which may not be rendered yet)
	var map_data = hex_map.map_data
	for y in range(MapConfig.MAP_HEIGHT):
		for x in range(MapConfig.MAP_WIDTH):
			var tile_type_str = map_data[y][x]

			# Map tile_type string to terrain type string (for terrain_cache)
			# For NPCs, land is walkable (opposite of ships)
			if tile_type_str == "water":  # Water
				pathfinding_system.set_tile(x, y, "water")  # Water (not walkable for NPCs)
			else:  # Land (all grasslands, cities, villages)
				pathfinding_system.set_tile(x, y, "land")  # Land (walkable for NPCs)

	print("NpcPathfindingBridge: Map initialized from map_data array (%d tiles)" % MapConfig.MAP_TOTAL_TILES)

## Request pathfinding for an NPC (async, callback receives result)
func request_path(npc_id: int, start: Vector2i, goal: Vector2i, callback: Callable) -> void:
	if not pathfinding_system:
		push_error("NpcPathfindingBridge: Not initialized!")
		return

	# Don't allow duplicate requests for same NPC
	if pending_requests.has(npc_id):
		push_warning("NpcPathfindingBridge: NPC ", npc_id, " already has pending path request")
		return

	# Register callback
	pending_requests[npc_id] = callback

	# Send request to Rust
	pathfinding_system.request_path(npc_id, start.x, start.y, goal.x, goal.y)

## Cancel pending request
func cancel_request(npc_id: int) -> void:
	pending_requests.erase(npc_id)

## Clear all data
func clear_all() -> void:
	if pathfinding_system:
		pathfinding_system.clear_all()
		pending_requests.clear()
