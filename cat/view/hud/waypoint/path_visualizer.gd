extends Node2D
class_name PathVisualizer

## Visualizes a ship's path with waypoint dots and connecting lines
## Automatically removes waypoints as the ship reaches them

var waypoint_markers: Array[WaypointMarker] = []
var path_line: Line2D = null
var ship: Node2D = null
var tile_map = null  # TileMapCompat wrapper for CustomTileRenderer

# Preload waypoint marker scene
const WaypointMarkerScene = preload("res://view/hud/waypoint/waypoint_marker.tscn")

func _ready() -> void:
	# Create Line2D for path connections
	path_line = Line2D.new()
	path_line.width = 3.0
	path_line.default_color = Color(0.2, 0.8, 1.0, 0.5)
	path_line.joint_mode = Line2D.LINE_JOINT_ROUND
	path_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	path_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	add_child(path_line)

## Display a path with waypoint markers
func show_path(path: Array[Vector2i], tile_map_ref, ship_ref: Node2D) -> void:
	clear_path()

	tile_map = tile_map_ref
	ship = ship_ref

	if path.size() < 2:
		return

	# Get entity ULID and name for waypoint markers
	var entity_ulid = PackedByteArray()
	var entity_name = "Unknown"
	if ship and "ulid" in ship:
		entity_ulid = ship.ulid

		# Determine entity name
		if ship is Jezza:
			entity_name = "Jezza Raptor"
		elif ship is NPC:
			# Check for water entities (vikings/ships)
			if "terrain_type" in ship and ship.terrain_type == NPC.TerrainType.WATER:
				entity_name = "Viking Ship"
			else:
				var script = ship.get_script()
				if script:
					var class_name_val = script.get_global_name()
					if not class_name_val.is_empty():
						entity_name = class_name_val
					else:
						entity_name = "NPC"
				else:
					entity_name = "NPC"

	# Skip first waypoint (ship's current position)
	for i in range(1, path.size()):
		var tile_coord = path[i]
		var world_pos = tile_map.map_to_local(tile_coord)

		# Create waypoint marker
		var marker = WaypointMarkerScene.instantiate()
		marker.position = world_pos
		marker.waypoint_index = i
		marker.entity_ulid = entity_ulid  # Store ULID for click handling
		marker.entity_name = entity_name  # Store name for display

		# Color gradient from cyan to blue
		var t = float(i) / float(path.size() - 1)
		var color = Color(0.2, 0.8, 1.0).lerp(Color(0.1, 0.4, 0.8), t)
		color.a = 0.8
		marker.set_color(color)

		add_child(marker)
		waypoint_markers.append(marker)

		# Add point to line
		path_line.add_point(world_pos)

## Remove the first waypoint (ship reached it)
func remove_first_waypoint() -> void:
	if waypoint_markers.size() == 0:
		return

	var marker = waypoint_markers[0]
	waypoint_markers.remove_at(0)
	marker.mark_reached()

	# Update line
	if path_line.get_point_count() > 0:
		path_line.remove_point(0)

## Clear all waypoints
func clear_path() -> void:
	for marker in waypoint_markers:
		if marker and is_instance_valid(marker):
			marker.queue_free()

	waypoint_markers.clear()

	if path_line:
		path_line.clear_points()

func _exit_tree() -> void:
	clear_path()
