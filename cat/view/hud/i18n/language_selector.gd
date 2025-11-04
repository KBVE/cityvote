extends CanvasLayer

# Language selector shown during game loading
# Allows player to choose their preferred language before game starts

@onready var panel: PanelContainer = $Panel
@onready var dimmer: ColorRect = $Dimmer
@onready var title_label: Label = $Panel/MarginContainer/VBoxContainer/TitleLabel
@onready var input_section: VBoxContainer = $Panel/MarginContainer/VBoxContainer/InputSection
@onready var seed_input: LineEdit = $Panel/MarginContainer/VBoxContainer/InputSection/SeedContainer/SeedInput
@onready var name_input: LineEdit = $Panel/MarginContainer/VBoxContainer/InputSection/NameContainer/NameInput
@onready var flag_container: HBoxContainer = $Panel/MarginContainer/VBoxContainer/FlagContainer
@onready var spinner = $Panel/MarginContainer/VBoxContainer/LoadingSection/SpinnerContainer/Spinner
@onready var progress_bar: ProgressBar = $Panel/MarginContainer/VBoxContainer/LoadingSection/ProgressBar
@onready var status_label: Label = $Panel/MarginContainer/VBoxContainer/LoadingSection/StatusLabel
@onready var discord_logo: SocialLogo = $Panel/MarginContainer/VBoxContainer/SocialContainer/DiscordLogo
@onready var twitch_logo: SocialLogo = $Panel/MarginContainer/VBoxContainer/SocialContainer/TwitchLogo

signal language_selected(language: int, world_seed: int, player_name: String)  # Old signal (for main.gd loading progress)
signal start_game(language: int, world_seed: int, player_name: String)  # New signal (for title.gd)

var flag_buttons: Array[TextureButton] = []
var pooled_flags: Array[PooledFlagIcon] = []  # Track pooled flag icons for cleanup
var selected_language: int = -1
var selected_button: TextureButton = null  # Track which button is selected
var world_seed: int = 12345
var player_name: String = "Player"
var start_button: Button = null

# Mode: "title" = show Start button, "loading" = show loading progress
var mode: String = "title"

# Loading progress tracking (for loading mode)
var total_steps: int = 5
var current_step: int = 0
var current_status_key: String = "ui.loading.initializing"
var language_rotation_timer: float = 0.0
var language_rotation_interval: float = 1.5
var current_language_index: int = 0

func _ready() -> void:
	# Create flag buttons for each language
	_create_flag_buttons()

	# Set title (always use alagard for "Select Your Language" in English)
	var font = Cache.get_font("alagard")
	if font:
		title_label.add_theme_font_override("font", font)

	# Initialize input fields
	_initialize_inputs()

	# Create Start button
	_create_start_button()

	# Setup social logos
	_setup_social_logos()

	# Title mode: show inputs and Start button, hide loading
	if mode == "title":
		flag_container.modulate.a = 1.0
		input_section.modulate.a = 1.0
		$Panel/MarginContainer/VBoxContainer/LoadingSection.visible = false
		if start_button:
			start_button.visible = true
			start_button.disabled = true  # Disabled until language selected
		if spinner:
			spinner.hide_spinner()  # Hide and stop spinner
		set_process(false)  # Don't need loading animation
	else:
		# Loading mode: start with flags and inputs at low opacity
		flag_container.modulate.a = 0.3
		input_section.modulate.a = 0.3
		if start_button:
			start_button.visible = false
		if spinner:
			spinner.show_spinner()  # Show and start spinner
		# Start rotating status messages
		set_process(true)
		_update_progress(0, "ui.loading.initializing")

	# Center on screen
	_center_panel()

func _process(delta: float) -> void:
	# Rotate through languages for status text (spinner rotation is automatic)
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
	if not Cluster:
		push_error("LanguageSelector: Cluster not available!")
		return

	var languages = I18n.get_available_languages()

	for lang in languages:
		var flag_info = I18n.get_flag_info(lang)
		var flag_name = flag_info["flag"]

		# Acquire pooled flag icon
		var flag_icon = Cluster.acquire("flag_icon") as PooledFlagIcon
		if not flag_icon:
			push_error("LanguageSelector: Failed to acquire flag icon from pool!")
			continue

		# Set flag
		flag_icon.set_flag(flag_name)
		pooled_flags.append(flag_icon)  # Track for cleanup

		# Wrap flag in a button for interactivity
		var button = TextureButton.new()
		button.custom_minimum_size = Vector2(48, 96)  # Match flag icon size
		button.mouse_filter = Control.MOUSE_FILTER_PASS

		# Connect hover and press
		button.mouse_entered.connect(_on_flag_hover.bind(button, true))
		button.mouse_exited.connect(_on_flag_hover.bind(button, false))
		button.pressed.connect(_on_flag_pressed.bind(lang))

		# Create container for flag and label
		var vbox = VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 4)

		# Add flag icon on top of button (for visuals)
		button.add_child(flag_icon)

		vbox.add_child(button)

		# Add language name label below
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

## Release all pooled flag icons back to the pool
func _release_pooled_flags() -> void:
	if not Cluster:
		return

	for flag_icon in pooled_flags:
		if is_instance_valid(flag_icon):
			# Remove from parent
			if flag_icon.get_parent():
				flag_icon.get_parent().remove_child(flag_icon)

			# Reset and return to pool
			flag_icon.reset_for_pool()
			Cluster.release("flag_icon", flag_icon)

	pooled_flags.clear()

## Override tree_exiting to clean up pooled flags
func _exit_tree() -> void:
	_release_pooled_flags()

func _on_flag_hover(button: TextureButton, is_hovered: bool) -> void:
	# Don't apply hover effect if this button is selected
	if button == selected_button:
		return

	if is_hovered:
		button.modulate = Color(1.2, 1.2, 1.0)  # Slight golden tint
		button.scale = Vector2(1.1, 1.1)
	else:
		button.modulate = Color.WHITE
		button.scale = Vector2.ONE

func _initialize_inputs() -> void:
	# Set default values
	seed_input.text = str(world_seed)
	name_input.text = player_name

	# Connect text changed signals
	seed_input.text_changed.connect(_on_seed_changed)
	name_input.text_changed.connect(_on_name_changed)

	# Apply font
	var font = Cache.get_font("alagard")
	if font:
		seed_input.add_theme_font_override("font", font)
		name_input.add_theme_font_override("font", font)

func _create_start_button() -> void:
	# Create Start button
	start_button = Button.new()
	start_button.text = "Start Game"
	start_button.custom_minimum_size = Vector2(200, 40)

	# Apply font
	var font = Cache.get_font("alagard")
	if font:
		start_button.add_theme_font_override("font", font)
		start_button.add_theme_font_size_override("font_size", 18)

	# Style the button
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = Color(0.2, 0.15, 0.1, 1.0)
	style_normal.border_color = Color(0.9, 0.7, 0.3, 1.0)
	style_normal.border_width_left = 2
	style_normal.border_width_top = 2
	style_normal.border_width_right = 2
	style_normal.border_width_bottom = 2
	style_normal.corner_radius_top_left = 8
	style_normal.corner_radius_top_right = 8
	style_normal.corner_radius_bottom_left = 8
	style_normal.corner_radius_bottom_right = 8

	var style_hover = style_normal.duplicate()
	style_hover.bg_color = Color(0.3, 0.2, 0.15, 1.0)

	var style_disabled = style_normal.duplicate()
	style_disabled.bg_color = Color(0.15, 0.12, 0.1, 1.0)
	style_disabled.border_color = Color(0.5, 0.4, 0.2, 1.0)

	start_button.add_theme_stylebox_override("normal", style_normal)
	start_button.add_theme_stylebox_override("hover", style_hover)
	start_button.add_theme_stylebox_override("pressed", style_hover)
	start_button.add_theme_stylebox_override("disabled", style_disabled)

	# Connect button press
	start_button.pressed.connect(_on_start_button_pressed)

	# Add to VBoxContainer (after FlagContainer)
	$Panel/MarginContainer/VBoxContainer.add_child(start_button)
	$Panel/MarginContainer/VBoxContainer.move_child(start_button, $Panel/MarginContainer/VBoxContainer.get_child_count() - 1)

func _on_start_button_pressed() -> void:
	# Emit start_game signal
	start_game.emit(selected_language, world_seed, player_name)

	# Close the selector
	queue_free()

func _on_seed_changed(new_text: String) -> void:
	# Parse seed (allow empty, int, or string)
	if new_text.is_empty():
		# Generate random seed within i32 bounds
		world_seed = randi() % 2147483647
	elif new_text.is_valid_int():
		# Use integer value, clamped to i32 range
		var parsed = new_text.to_int()
		world_seed = clampi(parsed, -2147483648, 2147483647)
	else:
		# Convert string to deterministic seed via hash
		world_seed = _string_to_seed(new_text)

func _on_name_changed(new_text: String) -> void:
	player_name = new_text if not new_text.is_empty() else "Player"

func _on_flag_pressed(language: int) -> void:
	# Set language
	I18n.set_language(language)
	selected_language = language

	# Find the button that was pressed
	var pressed_button: TextureButton = null
	var languages = I18n.get_available_languages()
	var lang_index = languages.find(language)
	if lang_index >= 0 and lang_index < flag_buttons.size():
		pressed_button = flag_buttons[lang_index]

	# Clear previous selection visual
	if selected_button and selected_button != pressed_button:
		selected_button.modulate = Color.WHITE
		selected_button.scale = Vector2.ONE

	# Highlight the selected button
	if pressed_button:
		selected_button = pressed_button
		selected_button.modulate = Color(1.5, 1.3, 0.5)  # Bright golden highlight
		selected_button.scale = Vector2(1.15, 1.15)  # Slightly larger

	# Enable Start button now that language is selected
	if start_button and mode == "title":
		start_button.disabled = false

	# In loading mode, fade out and close immediately
	if mode == "loading":
		_fade_out_and_close()

func _fade_out_and_close() -> void:
	# Fade out animation
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(panel, "modulate:a", 0.0, 0.5)
	tween.tween_property(dimmer, "modulate:a", 0.0, 0.5)
	await tween.finished

	# Emit signal with all values
	language_selected.emit(selected_language, world_seed, player_name)
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

	# Fade in the language flags and input fields
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(flag_container, "modulate:a", 1.0, 0.5)
	tween.tween_property(input_section, "modulate:a", 1.0, 0.5)
	tween.tween_property(spinner, "modulate:a", 0.0, 0.3)  # Fade out spinner
	await tween.finished

	# Hide spinner completely using universal spinner method
	if spinner:
		spinner.hide_spinner()

	# Wait for language selection
	if selected_language >= 0:
		_fade_out_and_close()

func _center_panel() -> void:
	# Center the panel on screen
	await get_tree().process_frame
	if panel:
		panel.position = (get_viewport().get_visible_rect().size - panel.size) / 2

## Skip language selection (use saved preference and defaults)
func skip_selection() -> void:
	selected_language = I18n.get_current_language()
	language_selected.emit(selected_language, world_seed, player_name)
	queue_free()

## Convert string to deterministic i32 seed (for text inputs like "home")
func _string_to_seed(text: String) -> int:
	# Simple hash function that generates deterministic i32 value from string
	var hash: int = 0
	for i in range(text.length()):
		var char_code = text.unicode_at(i)
		# Mix bits using prime multiplier and XOR
		hash = ((hash * 31) + char_code) & 0x7FFFFFFF  # Keep within positive i32 range

	# Allow negative seeds too, so map to full i32 range
	if hash > 1073741824:  # If in upper half of positive range
		hash = hash - 2147483648  # Map to negative range

	return hash

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
			# English, Spanish, and French use Latin characters
			return Cache.get_font("alagard")

## Setup social logos with click handling
func _setup_social_logos() -> void:
	if discord_logo and is_instance_valid(discord_logo):
		# Set logo type
		if discord_logo.has_method("set_logo"):
			discord_logo.set_logo(SocialLogo.LogoType.DISCORD)
		else:
			push_error("LanguageSelector: discord_logo missing set_logo method!")

		# Add clickable area
		var discord_button = TextureButton.new()
		discord_button.custom_minimum_size = Vector2(32, 32)
		discord_button.mouse_filter = Control.MOUSE_FILTER_PASS
		discord_button.pressed.connect(_on_discord_pressed)
		discord_button.mouse_entered.connect(_on_social_logo_hover.bind(discord_logo, true))
		discord_button.mouse_exited.connect(_on_social_logo_hover.bind(discord_logo, false))
		discord_logo.add_child(discord_button)
	else:
		push_warning("LanguageSelector: discord_logo not found or invalid")

	if twitch_logo and is_instance_valid(twitch_logo):
		# Set logo type
		if twitch_logo.has_method("set_logo"):
			twitch_logo.set_logo(SocialLogo.LogoType.TWITCH)
		else:
			push_error("LanguageSelector: twitch_logo missing set_logo method!")

		# Add clickable area
		var twitch_button = TextureButton.new()
		twitch_button.custom_minimum_size = Vector2(32, 32)
		twitch_button.mouse_filter = Control.MOUSE_FILTER_PASS
		twitch_button.pressed.connect(_on_twitch_pressed)
		twitch_button.mouse_entered.connect(_on_social_logo_hover.bind(twitch_logo, true))
		twitch_button.mouse_exited.connect(_on_social_logo_hover.bind(twitch_logo, false))
		twitch_logo.add_child(twitch_button)
	else:
		push_warning("LanguageSelector: twitch_logo not found or invalid")

## Handle social logo hover
func _on_social_logo_hover(logo: SocialLogo, is_hovered: bool) -> void:
	if not logo or not is_instance_valid(logo):
		return

	if is_hovered:
		logo.modulate = Color(1.2, 1.2, 1.0)  # Slight golden tint
		logo.scale = Vector2(1.15, 1.15)
	else:
		logo.modulate = Color.WHITE
		logo.scale = Vector2.ONE

## Handle Discord logo click
func _on_discord_pressed() -> void:
	Cache.open_url("https://kbve.com/discord/")

## Handle Twitch logo click
func _on_twitch_pressed() -> void:
	Cache.open_url("https://kbve.com/twitch/")
