extends Node

# Cache singleton - stores references to commonly used resources
# Prevents reloading and provides centralized access

# ===== RESOURCE COLORS =====
# Color constants for backward compatibility - these reference Resources.COLORS
# Prefer using Resources.get_color(resource_type) directly
const COLOR_GOLD: Color = Color(0.85, 0.7, 0.35)     # Gold/Yellow
const COLOR_FOOD: Color = Color(0.9, 0.3, 0.3)       # Red
const COLOR_LABOR: Color = Color(0.55, 0.45, 0.35)   # Brown/Tan (matches UI)
const COLOR_FAITH: Color = Color(0.7, 0.5, 0.9)      # Purple

# ===== STRINGS =====
# String-to-string mappings for UI text, translations, etc.
var strings: Dictionary = {}

# ===== FONTS =====
# Preloaded fonts for UI
var fonts: Dictionary = {}

# ===== SHADERS =====
# Preloaded shaders for effects
var shaders: Dictionary = {}

# ===== GAME CONSTANTS =====
# Centralized game configuration values
const MAX_HAND_SIZE: int = 15  # Maximum cards in hand

# ===== GAME REFERENCES =====
# Central references to key game systems (set by main.gd)
var tile_map = null  # TileMapCompat wrapper for coordinate conversion
var main_scene = null  # Reference to Main scene (set once on load)
var spinner_scene = null  # Cached spinner scene for reuse
var ui_references: Dictionary = {}  # Cache for UI references (topbar, etc.)
var entity_spawn_bridge = null  # Reference to EntitySpawnBridge singleton (Rust-authoritative spawning)

# ===== Z-INDEX CONSTANTS =====
# Centralized z-index values for proper rendering order
# All game objects use fixed z-index values (no tile_y based sorting)

# Background and static elements
const Z_INDEX_WATER_BG: int = -100         # Water background shader (below everything)
const Z_INDEX_TILES: int = 200             # Terrain tiles (fixed)
const Z_INDEX_HEX_HIGHLIGHT: int = 250     # Hex selection outline (above tiles)

# Game entities (fixed z-index, above tiles)
const Z_INDEX_ENTITIES: int = 500          # Base z-index for all entities
const Z_INDEX_NPCS: int = 501              # NPCs
const Z_INDEX_SHIPS: int = 502             # Ships
const Z_INDEX_CARDS: int = 503             # Placed cards

# UI and overlays (fixed high values, above all game objects)
# Note: Godot's max z_index is RenderingServer::CANVAS_ITEM_Z_MAX (4096)
const Z_INDEX_WAYPOINTS: int = 3000        # Path visualizers and waypoint markers
const Z_INDEX_GHOST_CARD: int = 3500       # Ghost card preview while dragging
const Z_INDEX_UI: int = 4000               # UI elements (TileInfo, etc.)

func _ready():
	_load_fonts()
	_load_shaders()
	_load_strings()
	_load_spinner_scene()
	_init_entity_spawn_bridge()

# ===== SCENE REFERENCES MANAGEMENT =====

## Set main scene reference (called once when Main scene loads)
func set_main_scene(scene: Node) -> void:
	if scene == null:
		push_error("Cache: Attempted to set null main_scene reference")
		return
	main_scene = scene

## Get main scene reference
func get_main_scene() -> Node:
	if main_scene == null:
		push_warning("Cache: main_scene not initialized yet")
	return main_scene

## Cache a UI reference by name
func set_ui_reference(reference_name: String, node: Node) -> void:
	if node == null:
		push_error("Cache: Attempted to cache null UI reference for '%s'" % reference_name)
		return
	ui_references[reference_name] = node

## Get a cached UI reference
func get_ui_reference(reference_name: String) -> Node:
	if not ui_references.has(reference_name):
		push_warning("Cache: UI reference '%s' not found" % reference_name)
		return null
	return ui_references[reference_name]

## Load spinner scene for reuse
func _load_spinner_scene() -> void:
	var spinner_path = "res://view/hud/spinner/spinner.tscn"
	if ResourceLoader.exists(spinner_path):
		spinner_scene = load(spinner_path)
	else:
		push_warning("Cache: Could not find spinner scene at " + spinner_path)

## Get spinner scene (already loaded)
func get_spinner_scene() -> PackedScene:
	return spinner_scene

## Initialize EntitySpawnBridge reference (called in _ready)
func _init_entity_spawn_bridge() -> void:
	entity_spawn_bridge = get_node("/root/EntitySpawnBridge")
	if entity_spawn_bridge == null:
		push_error("Cache: Failed to get EntitySpawnBridge autoload reference")
	else:
		print("Cache: EntitySpawnBridge reference initialized")

## Get EntitySpawnBridge reference
func get_entity_spawn_bridge() -> Node:
	if entity_spawn_bridge == null:
		push_error("Cache: entity_spawn_bridge not initialized")
	return entity_spawn_bridge

# Set tile_map reference (called by main.gd after hex_map initializes)
func set_tile_map(tmap) -> void:
	if tmap == null:
		push_error("Cache: Attempted to set null tile_map reference")
		return
	tile_map = tmap

# Get tile_map reference
func get_tile_map():
	if tile_map == null:
		push_error("Cache: tile_map not initialized - call set_tile_map() first")
	return tile_map

# Load all fonts
func _load_fonts():
	# Alagard font (main game font - Latin characters only)
	var alagard_path = "res://view/font/alagard.ttf"
	if ResourceLoader.exists(alagard_path):
		fonts["alagard"] = load(alagard_path)
	else:
		push_warning("Cache: Could not find font at " + alagard_path)

	# Japanese font (TODO: Add a font that supports Japanese characters)
	var japanese_font_path = "res://view/font/japanese.ttf"
	if ResourceLoader.exists(japanese_font_path):
		fonts["japanese"] = load(japanese_font_path)
	else:
		# Fallback to system font or alagard
		fonts["japanese"] = fonts.get("alagard")
		push_warning("Cache: Japanese font not found, using fallback")

	# Chinese font (TODO: Add a font that supports Chinese characters)
	var chinese_font_path = "res://view/font/chinese.ttf"
	if ResourceLoader.exists(chinese_font_path):
		fonts["chinese"] = load(chinese_font_path)
	else:
		# Fallback to system font or alagard
		fonts["chinese"] = fonts.get("alagard")
		push_warning("Cache: Chinese font not found, using fallback")

	# Hindi font (TODO: Add a font that supports Devanagari script)
	var hindi_font_path = "res://view/font/hindi.ttf"
	if ResourceLoader.exists(hindi_font_path):
		fonts["hindi"] = load(hindi_font_path)
	else:
		# Fallback to system font or alagard
		fonts["hindi"] = fonts.get("alagard")
		push_warning("Cache: Hindi font not found, using fallback")

# Load all shaders
func _load_shaders():
	# Wave shader (for sprites on water)
	var wave_shader_path = "res://shader/with_wave.gdshader"
	if ResourceLoader.exists(wave_shader_path):
		shaders["with_wave"] = load(wave_shader_path)
	else:
		push_warning("Cache: Could not find shader at " + wave_shader_path)

# Load string mappings
func _load_strings():
	# Tile type display names
	strings["grassland"] = "Grassland"
	strings["water"] = "Water"
	strings["city"] = "City"
	strings["village"] = "Village"

	# UI labels
	strings["tile_info_title"] = "Tile Info"
	strings["coords_label"] = "Coords: %s"
	strings["type_label"] = "Type: %s"
	strings["world_label"] = "World: %s"

# Get a font by name
func get_font(font_name: String) -> Font:
	if fonts.has(font_name):
		return fonts[font_name]
	push_warning("Cache: Font not found: " + font_name)
	return null

# Get font appropriate for current language (auto-switches based on I18n.current_language)
func get_font_for_current_language() -> Font:
	var current_lang = I18n.get_current_language()
	match current_lang:
		I18n.Language.JAPANESE:
			return fonts.get("japanese", fonts.get("alagard"))
		I18n.Language.CHINESE:
			return fonts.get("chinese", fonts.get("alagard"))
		I18n.Language.HINDI:
			# Hindi uses Devanagari script - needs special font too
			return fonts.get("hindi", fonts.get("alagard"))
		_:
			# English and Spanish use Latin characters - alagard works
			return fonts.get("alagard")

# Get a string by key
func get_string(key: String, default: String = "") -> String:
	if strings.has(key):
		return strings[key]
	if default != "":
		return default
	push_warning("Cache: String key not found: " + key)
	return key

# Add or update a string mapping
func set_string(key: String, value: String):
	strings[key] = value

# Check if a font exists
func has_font(font_name: String) -> bool:
	return fonts.has(font_name)

# Check if a string key exists
func has_string(key: String) -> bool:
	return strings.has(key)

# Get a shader by name
func get_shader(shader_name: String) -> Shader:
	if shaders.has(shader_name):
		return shaders[shader_name]
	push_warning("Cache: Shader not found: " + shader_name)
	return null

# Check if a shader exists
func has_shader(shader_name: String) -> bool:
	return shaders.has(shader_name)

# Create a ShaderMaterial from cached shader with optional parameters
func create_shader_material(shader_name: String, params: Dictionary = {}) -> ShaderMaterial:
	var shader = get_shader(shader_name)
	if shader == null:
		return null

	var material = ShaderMaterial.new()
	material.shader = shader

	# Apply parameters if provided
	for param_name in params:
		material.set_shader_parameter(param_name, params[param_name])

	return material

# ===== URL OPENING =====

## Universal URL opening function
## Opens both web URLs (http/https) and native URLs (steam://, discord://, etc.)
## @param url: The URL to open
## @return: Error code from OS.shell_open() (0 = OK)
func open_url(url: String) -> int:
	if url.is_empty():
		push_warning("Cache: Attempted to open empty URL")
		return ERR_INVALID_PARAMETER

	# Validate URL format (basic check)
	if not (url.begins_with("http://") or url.begins_with("https://") or
			url.begins_with("steam://") or url.begins_with("discord://") or
			url.begins_with("twitch://") or url.contains("://")):
		push_warning("Cache: Invalid URL format: %s" % url)
		return ERR_INVALID_PARAMETER

	# Open URL using OS shell
	var result = OS.shell_open(url)

	if result != OK:
		push_error("Cache: Failed to open URL: %s (Error code: %d)" % [url, result])

	return result
