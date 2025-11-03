extends TextureRect
class_name PooledFlagIcon

## Pooled flag icon for language selector and other UI
## Uses AtlasTexture for efficient rendering from combined atlas

# Combined atlas (cached globally across all flag icons)
static var _combined_atlas: Texture2D = null

func _ready() -> void:
	# Load combined atlas on first use (cached globally)
	if _combined_atlas == null:
		_combined_atlas = load(I18n.COMBINED_ATLAS_PATH)

## Set the flag to display
## flag_name: Name of the flag (e.g., "bavaria", "british", "china")
func set_flag(flag_name: String) -> void:
	if flag_name.is_empty():
		texture = null
		visible = false
		return

	# Get flag frame from I18n system
	var flag_frame = I18n.get_flag_frame(flag_name)

	# Create AtlasTexture
	var atlas_texture = AtlasTexture.new()
	atlas_texture.atlas = _combined_atlas
	atlas_texture.region = flag_frame

	# Apply texture
	texture = atlas_texture
	visible = true
	modulate = Color.WHITE

## Reset for pooling
func reset_for_pool() -> void:
	texture = null
	visible = false
	modulate = Color.WHITE
