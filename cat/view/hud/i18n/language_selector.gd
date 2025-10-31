extends CanvasLayer

# Language selector shown during game loading
# Allows player to choose their preferred language before game starts

@onready var panel: PanelContainer = $Panel
@onready var dimmer: ColorRect = $Dimmer
@onready var title_label: Label = $Panel/MarginContainer/VBoxContainer/TitleLabel
@onready var flag_container: HBoxContainer = $Panel/MarginContainer/VBoxContainer/FlagContainer
@onready var spinner: ColorRect = $Panel/MarginContainer/VBoxContainer/LoadingSection/SpinnerContainer/Spinner
@onready var progress_bar: ProgressBar = $Panel/MarginContainer/VBoxContainer/LoadingSection/ProgressBar
@onready var status_label: Label = $Panel/MarginContainer/VBoxContainer/LoadingSection/StatusLabel

signal language_selected(language: int)

var flag_buttons: Array[TextureButton] = []
var selected_language: int = -1

# Loading progress tracking
var total_steps: int = 5
var current_step: int = 0
var current_status_key: String = "ui.loading.initializing"
var language_rotation_timer: float = 0.0
var language_rotation_interval: float = 1.5
var current_language_index: int = 0
var spinner_rotation: float = 0.0

func _ready() -> void:
	# Create flag buttons for each language
	_create_flag_buttons()

	# Set title (always use alagard for "Select Your Language" in English)
	var font = Cache.get_font("alagard")
	if font:
		title_label.add_theme_font_override("font", font)

	# Start with flags at low opacity
	flag_container.modulate.a = 0.3

	# Center on screen
	_center_panel()

	# Start rotating status messages and spinner
	set_process(true)
	_update_progress(0, "ui.loading.initializing")

func _process(delta: float) -> void:
	# Rotate spinner (only if visible)
	if spinner.visible:
		spinner_rotation += delta * 5.0  # 5 radians per second (faster rotation)
		spinner.rotation = spinner_rotation

	# Rotate through languages for status text
	language_rotation_timer += delta
	if language_rotation_timer >= language_rotation_interval:
		language_rotation_timer = 0.0
		_rotate_language()

## Rotate to next language for status message
func _rotate_language() -> void:
	var languages = I18n.get_available_languages()
	current_language_index = (current_language_index + 1) % languages.size()
	var lang = languages[current_language_index]

	# Get translated text for current status in this language
	var translated = I18n.get_translation_for_language(current_status_key, lang)
	status_label.text = translated

	# Apply appropriate font for this language
	var font = _get_font_for_language(lang)
	if font:
		status_label.add_theme_font_override("font", font)
		status_label.add_theme_font_size_override("font_size", 12)

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
	tween.set_parallel(true)
	tween.tween_property(panel, "modulate:a", 0.0, 0.5)
	tween.tween_property(dimmer, "modulate:a", 0.0, 0.5)
	await tween.finished

	# Emit signal and hide
	language_selected.emit(selected_language)
	queue_free()

## Update loading progress
func _update_progress(step: int, status_key: String) -> void:
	current_step = step
	current_status_key = status_key
	var progress = (float(current_step) / float(total_steps)) * 100.0

	progress_bar.value = progress
	_rotate_language()  # Immediately show new status

## Loading step functions (called from main.gd)
func set_map_generation() -> void:
	_update_progress(1, "ui.loading.generating_map")

func set_chunk_rendering() -> void:
	_update_progress(2, "ui.loading.rendering_chunks")

func set_pathfinding_init() -> void:
	_update_progress(3, "ui.loading.pathfinding")

func set_spawning_entities() -> void:
	_update_progress(4, "ui.loading.spawning_entities")

func set_complete() -> void:
	_update_progress(5, "ui.loading.complete")

	# Fade in the language flags
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(flag_container, "modulate:a", 1.0, 0.5)
	tween.tween_property(spinner, "modulate:a", 0.0, 0.3)  # Fade out spinner
	await tween.finished

	# Hide spinner completely
	spinner.visible = false

	# Wait for language selection
	if selected_language >= 0:
		_fade_out_and_close()

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
