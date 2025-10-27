extends Node

# Cache singleton - stores references to commonly used resources
# Prevents reloading and provides centralized access

# ===== STRINGS =====
# String-to-string mappings for UI text, translations, etc.
var strings: Dictionary = {}

# ===== FONTS =====
# Preloaded fonts for UI
var fonts: Dictionary = {}

# ===== SHADERS =====
# Preloaded shaders for effects
var shaders: Dictionary = {}

func _ready():
	_load_fonts()
	_load_shaders()
	_load_strings()

# Load all fonts
func _load_fonts():
	# Alagard font (main game font)
	var alagard_path = "res://view/font/alagard.ttf"
	if ResourceLoader.exists(alagard_path):
		fonts["alagard"] = load(alagard_path)
	else:
		push_warning("Cache: Could not find font at " + alagard_path)

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
