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
## PROCEDURAL WORLD: No initialization needed - chunks are loaded on-demand
func init_map(hex_map: Node) -> void:
	if not pathfinding_system:
		push_error("NpcPathfindingBridge: Not initialized!")
		return

	# PROCEDURAL WORLD: Skip full map initialization
	# Terrain cache is populated incrementally as chunks are generated
	# The WorldGenerator provides terrain data on-demand
	print("NpcPathfindingBridge: init_map called - using on-demand chunk loading (infinite world)")
	print("NpcPathfindingBridge: Map initialized for infinite world (0 tiles pre-loaded, chunks loaded on-demand)")

## Load a chunk into the pathfinding terrain cache (for procedural world)
func load_chunk(chunk_coords: Vector2i, tile_data: Array) -> void:
	if not pathfinding_system:
		return

	# Convert chunk tile data to terrain cache format
	# For NPCs: land is walkable, water is not (opposite of ships)
	# tile_data contains: {tile_index: int, x: int, y: int}
	# tile_index matches atlas: 0-3,5-6 = grassland variants, 4 = water
	for tile in tile_data:
		var x = tile["x"]
		var y = tile["y"]
		var tile_index = tile["tile_index"]

		# Set terrain type in Rust pathfinding cache
		if tile_index == 4:
			pathfinding_system.set_tile(x, y, "water")  # Not walkable for NPCs
		else:
			pathfinding_system.set_tile(x, y, "land")  # Walkable for NPCs

	print("NpcPathfindingBridge: Loaded chunk %v (%d tiles) into pathfinding cache" % [chunk_coords, tile_data.size()])

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
