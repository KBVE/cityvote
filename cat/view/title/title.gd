extends Node2D

# Title screen - shows language selector and starts the game
# This is the first scene loaded, then transitions to main.tscn

var language_selector = null
var selected_language: int = -1
var world_seed: int = 12345
var player_name: String = "Player"

func _ready():
	# Show language selector (includes language, world seed, and player name inputs)
	_show_language_selector()

## Show language selector
func _show_language_selector() -> void:
	# Load language selector scene
	var selector_scene = load("res://view/hud/i18n/language_selector.tscn")
	if not selector_scene:
		push_error("Title: Failed to load language selector scene!")
		return

	language_selector = selector_scene.instantiate()
	add_child(language_selector)

	# Connect to start_game signal (emitted when user clicks Start button)
	if language_selector.has_signal("start_game"):
		language_selector.start_game.connect(_on_start_game)

	print("Title: Language selector displayed")

## Handle start game button - transition to main scene
func _on_start_game(language: int, world_seed_input: int, player_name_input: String) -> void:
	selected_language = language
	world_seed = world_seed_input
	player_name = player_name_input

	print("Title: Starting game - Language: %d, World Seed: %d, Player: %s" % [language, world_seed, player_name])

	# Apply world seed to MapConfig before loading main scene
	if MapConfig:
		MapConfig.world_seed = world_seed
		print("Title: World seed set to %d" % world_seed)

	# TODO: Store player_name (could be saved to a PlayerData singleton)
	print("Title: Player name set to '%s'" % player_name)

	# Transition to main scene
	_load_main_scene()

## Load the main game scene
func _load_main_scene() -> void:
	print("Title: Loading main scene...")
	get_tree().change_scene_to_file("res://view/main/main.tscn")
