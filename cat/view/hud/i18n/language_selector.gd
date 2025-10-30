extends CanvasLayer

# Language selector shown during game loading
# Allows player to choose their preferred language before game starts

@onready var panel: PanelContainer = $Panel
@onready var title_label: Label = $Panel/MarginContainer/VBoxContainer/TitleLabel
@onready var flag_container: HBoxContainer = $Panel/MarginContainer/VBoxContainer/FlagContainer

signal language_selected(language: int)

var flag_buttons: Array[TextureButton] = []
var selected_language: int = -1

func _ready() -> void:
	# Create flag buttons for each language
	_create_flag_buttons()

	# Set title (always use alagard for "Select Your Language" in English)
	var font = Cache.get_font("alagard")
	if font:
		title_label.add_theme_font_override("font", font)

	# Center on screen
	_center_panel()

func _create_flag_buttons() -> void:
	var languages = I18n.get_available_languages()

	for lang in languages:
		var flag_info = I18n.get_flag_info(lang)
		var flag_name = flag_info["flag"]
		var atlas_name = flag_info["atlas"]

		# Create button
		var button = TextureButton.new()
		button.custom_minimum_size = Vector2(48, 96)  # 16x32 flag scaled 3x
		button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		button.ignore_texture_size = true

		# Load flag texture from atlas
		var texture = _load_flag_texture(flag_name, atlas_name)
		if texture:
			button.texture_normal = texture
			button.texture_hover = texture
			button.texture_pressed = texture

			# Add hover effect via modulate
			button.mouse_entered.connect(_on_flag_hover.bind(button, true))
			button.mouse_exited.connect(_on_flag_hover.bind(button, false))

		# Connect button press
		button.pressed.connect(_on_flag_pressed.bind(lang))

		# Add language name label below flag
		var vbox = VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 4)

		vbox.add_child(button)

		var lang_label = Label.new()
		lang_label.text = I18n.get_language_display_name(lang)
		lang_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

		# Get appropriate font for this specific language
		var font = _get_font_for_language(lang)
		if font:
			lang_label.add_theme_font_override("font", font)
			lang_label.add_theme_font_size_override("font_size", 12)

		vbox.add_child(lang_label)

		flag_container.add_child(vbox)
		flag_buttons.append(button)

func _load_flag_texture(flag_name: String, atlas_name: String) -> AtlasTexture:
	# Load the atlas texture
	var atlas_path = "res://view/hud/i18n/%s.png" % atlas_name
	var atlas = load(atlas_path)
	if not atlas:
		push_error("LanguageSelector: Failed to load atlas: %s" % atlas_path)
		return null

	# Get hardcoded flag frame data from I18n (no JSON loading needed)
	var frame_region = I18n.get_flag_frame(flag_name)

	# Create AtlasTexture
	var atlas_texture = AtlasTexture.new()
	atlas_texture.atlas = atlas
	atlas_texture.region = frame_region

	return atlas_texture

func _on_flag_hover(button: TextureButton, is_hovered: bool) -> void:
	if is_hovered:
		button.modulate = Color(1.2, 1.2, 1.0)  # Slight golden tint
		button.scale = Vector2(1.1, 1.1)
	else:
		button.modulate = Color.WHITE
		button.scale = Vector2.ONE

func _on_flag_pressed(language: int) -> void:
	# Set language
	I18n.set_language(language)
	selected_language = language

	# Fade out and close
	_fade_out_and_close()

func _fade_out_and_close() -> void:
	# Fade out animation
	var tween = create_tween()
	tween.tween_property(panel, "modulate:a", 0.0, 0.3)
	await tween.finished

	# Emit signal and hide
	language_selected.emit(selected_language)
	queue_free()

func _center_panel() -> void:
	# Center the panel on screen
	await get_tree().process_frame
	if panel:
		panel.position = (get_viewport().get_visible_rect().size - panel.size) / 2

## Skip language selection (use saved preference)
func skip_selection() -> void:
	selected_language = I18n.get_current_language()
	language_selected.emit(selected_language)
	queue_free()

## Get font for a specific language (used for language selector labels)
func _get_font_for_language(lang: int) -> Font:
	match lang:
		I18n.Language.JAPANESE:
			return Cache.get_font("japanese")
		I18n.Language.CHINESE:
			return Cache.get_font("chinese")
		I18n.Language.HINDI:
			return Cache.get_font("hindi")
		_:
			# English and Spanish use Latin characters
			return Cache.get_font("alagard")
