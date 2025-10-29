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
