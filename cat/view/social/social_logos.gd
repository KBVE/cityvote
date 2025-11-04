extends Control
class_name SocialLogo

## SocialLogo - Displays social media logos using sprite atlas
## Uses shader-based rendering for efficient logo display

# Logo constants
enum LogoType {
	DISCORD = 0,
	TWITCH = 1
}

# Atlas layout constants
const ATLAS_WIDTH = 64
const ATLAS_HEIGHT = 32
const LOGO_SIZE = 32
const TOTAL_LOGOS = 2

# Preload atlas texture
const ATLAS_TEXTURE = preload("res://view/social/sprite_social_logos_atlas.png")

# Current logo being displayed
var current_logo: LogoType = LogoType.DISCORD

# TextureRect and material references
@onready var texture_rect: TextureRect = $TextureRect

func _ready() -> void:
	if not texture_rect:
		push_error("SocialLogo: TextureRect node not found")
		return

	# Set up texture rect with atlas texture
	texture_rect.texture = ATLAS_TEXTURE

	# Duplicate material for per-instance control (only if material exists)
	if texture_rect.material:
		texture_rect.material = texture_rect.material.duplicate()
	else:
		push_warning("SocialLogo: TextureRect has no material in scene - shader may not work")

	# Initialize with current logo
	set_logo(current_logo)

## Set which logo to display
func set_logo(logo_type: LogoType) -> void:
	current_logo = logo_type

	if not texture_rect or not texture_rect.material:
		return

	# Update shader parameters
	texture_rect.material.set_shader_parameter("logo_index", int(logo_type))
	texture_rect.material.set_shader_parameter("total_logos", TOTAL_LOGOS)
	texture_rect.material.set_shader_parameter("atlas_texture", ATLAS_TEXTURE)

## Get current logo type
func get_logo() -> LogoType:
	return current_logo

## Set logo by name (case-insensitive)
func set_logo_by_name(logo_name: String) -> void:
	var name_lower = logo_name.to_lower()
	match name_lower:
		"discord":
			set_logo(LogoType.DISCORD)
		"twitch":
			set_logo(LogoType.TWITCH)
		_:
			push_warning("Unknown logo name: %s" % logo_name)

## Get logo name from type
static func get_logo_name(logo_type: LogoType) -> String:
	match logo_type:
		LogoType.DISCORD:
			return "Discord"
		LogoType.TWITCH:
			return "Twitch"
		_:
			return "Unknown"

## Get all available logo names
static func get_available_logos() -> Array[String]:
	return ["Discord", "Twitch"]
