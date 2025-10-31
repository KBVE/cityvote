extends CanvasLayer

## Loading progress overlay
## Shows actual game initialization progress beyond Godot's built-in loading bar

@onready var background: ColorRect = $ColorRect
@onready var center_container: CenterContainer = $CenterContainer
@onready var title_label: Label = $CenterContainer/VBoxContainer/TitleLabel
@onready var progress_bar: ProgressBar = $CenterContainer/VBoxContainer/ProgressBar
@onready var status_label: Label = $CenterContainer/VBoxContainer/StatusLabel

# Progress tracking
var total_steps: int = 5
var current_step: int = 0

# Multi-language rotation
var language_rotation_timer: float = 0.0
var language_rotation_interval: float = 1.5  # Rotate every 1.5 seconds
var current_language_index: int = 0
var current_status_key: String = "ui.loading.initializing"

func _ready() -> void:
	# Set title (static in English for now)
	var font = Cache.get_font("alagard")
	if font:
		title_label.add_theme_font_override("font", font)
		title_label.add_theme_font_size_override("font_size", 24)
	title_label.text = "Loading..."

	# Start language rotation
	set_process(true)

	# Set initial state
	_update_progress(0, "ui.loading.initializing")

func _process(delta: float) -> void:
	# Rotate through languages for status text
	language_rotation_timer += delta
	if language_rotation_timer >= language_rotation_interval:
		language_rotation_timer = 0.0
		_rotate_language()

## Rotate to next language
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
		status_label.add_theme_font_size_override("font_size", 14)

## Get font for a specific language
func _get_font_for_language(lang: int) -> Font:
	match lang:
		I18n.Language.JAPANESE:
			return Cache.get_font("japanese")
		I18n.Language.CHINESE:
			return Cache.get_font("chinese")
		I18n.Language.HINDI:
			return Cache.get_font("hindi")
		_:
			return Cache.get_font("alagard")

## Update progress bar and status text
func _update_progress(step: int, status_key: String) -> void:
	current_step = step
	current_status_key = status_key
	var progress = (float(current_step) / float(total_steps)) * 100.0

	progress_bar.value = progress

	# Immediately show in current language rotation
	_rotate_language()

	# Force UI update
	await get_tree().process_frame

## Set step 1: Map generation
func set_map_generation() -> void:
	_update_progress(1, "ui.loading.generating_map")

## Set step 2: Rendering initial chunks
func set_chunk_rendering() -> void:
	_update_progress(2, "ui.loading.rendering_chunks")

## Set step 3: Initializing pathfinding
func set_pathfinding_init() -> void:
	_update_progress(3, "ui.loading.pathfinding")

## Set step 4: Spawning entities
func set_spawning_entities() -> void:
	_update_progress(4, "ui.loading.spawning_entities")

## Set step 5: Complete
func set_complete() -> void:
	_update_progress(5, "ui.loading.complete")
	await get_tree().create_timer(0.5).timeout
	_fade_out()

## Fade out and remove
func _fade_out() -> void:
	var tween = create_tween()
	tween.set_parallel(true)  # Fade both elements at the same time
	tween.tween_property(background, "modulate:a", 0.0, 0.5)
	tween.tween_property(center_container, "modulate:a", 0.0, 0.5)
	await tween.finished
	queue_free()
