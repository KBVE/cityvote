extends Node

# Pathfinding singleton - handles A* pathfinding for ships and units

# Hex grid directions for staggered odd-row offset coordinates
# These offsets depend on whether the row is even or odd
const HEX_DIRECTIONS_EVEN = [
	Vector2i(1, 0),   # East
	Vector2i(-1, 0),  # West
	Vector2i(0, -1),  # North-West
	Vector2i(1, -1),  # North-East
	Vector2i(0, 1),   # South-West
	Vector2i(1, 1),   # South-East
]

const HEX_DIRECTIONS_ODD = [
	Vector2i(1, 0),   # East
	Vector2i(-1, 0),  # West
	Vector2i(-1, -1), # North-West
	Vector2i(0, -1),  # North-East
	Vector2i(-1, 1),  # South-West
	Vector2i(0, 1),   # South-East
]

# Get hex neighbors based on staggered grid
func get_hex_neighbors(coords: Vector2i) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	var directions = HEX_DIRECTIONS_ODD if coords.y % 2 == 1 else HEX_DIRECTIONS_EVEN

	for direction in directions:
		neighbors.append(coords + direction)

	return neighbors

# Find valid water tiles adjacent to a position, excluding occupied tiles
func find_valid_adjacent_water_tiles(
	start_tile: Vector2i,
	hex_map,
	occupied_tiles: Dictionary,
	current_ship = null
) -> Array[Vector2i]:
	var valid_tiles: Array[Vector2i] = []
	var neighbors = get_hex_neighbors(start_tile)

	for neighbor in neighbors:
		# No bounds check - infinite world support

		# Check if water tile (atlas index 4 = water)
		var tile_index = hex_map.get_tile_type_at_coords(neighbor)
		if tile_index != 4:
			continue

		# Check if occupied (allow current ship's own tile)
		if occupied_tiles.has(neighbor) and occupied_tiles[neighbor] != current_ship:
			continue

		valid_tiles.append(neighbor)

	return valid_tiles

# A* pathfinding for hex grid
# Returns array of Vector2i coordinates from start to goal (excluding start, including goal)
func find_path(
	start: Vector2i,
	goal: Vector2i,
	hex_map,
	occupied_tiles: Dictionary,
	current_ship = null,
	max_path_length: int = 50
) -> Array[Vector2i]:
	# Check if goal is valid
	if not _is_tile_valid(goal, hex_map, occupied_tiles, current_ship):
		return []

	# A* algorithm
	var open_set: Array[Vector2i] = [start]
	var came_from: Dictionary = {}
	var g_score: Dictionary = {start: 0}
	var f_score: Dictionary = {start: _heuristic(start, goal)}

	while open_set.size() > 0:
		# Get node with lowest f_score
		var current = _get_lowest_f_score(open_set, f_score)

		# Check if we reached goal
		if current == goal:
			return _reconstruct_path(came_from, current)

		open_set.erase(current)

		# Check all neighbors
		var neighbors = get_hex_neighbors(current)
		for neighbor in neighbors:
			# Skip invalid tiles
			if not _is_tile_valid(neighbor, hex_map, occupied_tiles, current_ship):
				continue

			# Calculate tentative g_score
			var tentative_g_score = g_score[current] + 1

			# Check if this path is better
			if not g_score.has(neighbor) or tentative_g_score < g_score[neighbor]:
				# This path is the best so far
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g_score
				f_score[neighbor] = tentative_g_score + _heuristic(neighbor, goal)

				if neighbor not in open_set:
					open_set.append(neighbor)

		# Prevent infinite loops
		if g_score[current] > max_path_length:
			break

	# No path found
	return []

# Find a random reachable water tile within range
func find_random_destination(
	start: Vector2i,
	hex_map,
	occupied_tiles: Dictionary,
	current_ship = null,
	min_distance: int = 2,
	max_distance: int = 5
) -> Vector2i:
	# Try to find valid water tiles within range
	var valid_destinations: Array[Vector2i] = []

	# Search in expanding rings
	for distance in range(min_distance, max_distance + 1):
		var tiles_at_distance = _get_tiles_at_distance(start, distance)

		for tile in tiles_at_distance:
			if _is_tile_valid(tile, hex_map, occupied_tiles, current_ship):
				valid_destinations.append(tile)

	# Return random valid destination
	if valid_destinations.size() > 0:
		return valid_destinations[randi() % valid_destinations.size()]

	# Fallback: return start if no valid destinations
	return start

# Private helper functions

func _is_tile_valid(tile: Vector2i, hex_map, occupied_tiles: Dictionary, current_ship = null) -> bool:
	# No bounds check - infinite world support

	# Check if water tile (atlas index 4 = water)
	var tile_index = hex_map.get_tile_type_at_coords(tile)
	if tile_index != 4:
		return false

	# Check if occupied (allow current ship's own tile)
	if occupied_tiles.has(tile) and occupied_tiles[tile] != current_ship:
		return false

	return true

func _heuristic(a: Vector2i, b: Vector2i) -> float:
	# Hex distance heuristic (Manhattan distance approximation)
	var dx = abs(a.x - b.x)
	var dy = abs(a.y - b.y)
	return dx + max(0, (dy - dx) / 2.0)

func _get_lowest_f_score(open_set: Array[Vector2i], f_score: Dictionary) -> Vector2i:
	var lowest = open_set[0]
	var lowest_score = f_score.get(lowest, INF)

	for node in open_set:
		var score = f_score.get(node, INF)
		if score < lowest_score:
			lowest = node
			lowest_score = score

	return lowest

func _reconstruct_path(came_from: Dictionary, current: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [current]

	while came_from.has(current):
		current = came_from[current]
		path.insert(0, current)

	# Remove start position (first element)
	if path.size() > 0:
		path.remove_at(0)

	return path

func _get_tiles_at_distance(center: Vector2i, distance: int) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []

	# Approximate ring search for hex grid
	for x in range(center.x - distance, center.x + distance + 1):
		for y in range(center.y - distance, center.y + distance + 1):
			var tile = Vector2i(x, y)
			var dist = _heuristic(center, tile)
			if dist >= distance - 0.5 and dist <= distance + 0.5:
				tiles.append(tile)

	return tiles
