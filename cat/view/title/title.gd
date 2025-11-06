extends Node2D

# Title screen - shows language selector and starts the game
# This is the first scene loaded, then transitions to main.tscn

var language_selector = null
var selected_language: int = -1
var world_seed: int = 12345
var player_name: String = "Player"
var hcaptcha_test = null

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

	# Connect to test_captcha signal (emitted when user clicks Test hCaptcha button)
	if language_selector.has_signal("test_captcha"):
		language_selector.test_captcha.connect(_on_test_captcha)

## Handle start game button - transition to main scene
func _on_start_game(language: int, world_seed_input: int, player_name_input: String) -> void:
	selected_language = language
	world_seed = world_seed_input
	player_name = player_name_input

	# Apply world seed to MapConfig before loading main scene
	if MapConfig:
		MapConfig.world_seed = world_seed
	else:
		push_error("Title: MapConfig not available!")

	# Store player name to Cache for IRC and other systems
	if Cache:
		Cache.set_value("player_name", player_name)
		print("[Title] Player name saved to Cache: ", player_name)
	else:
		push_error("Title: Cache not available!")

	# Transition to main scene
	_load_main_scene()

## Load the main game scene
func _load_main_scene() -> void:
	get_tree().change_scene_to_file("res://view/main/main.tscn")

## Handle hCaptcha test button - show hCaptcha test interface
func _on_test_captcha() -> void:
	print("[Title] hCaptcha test requested")

	# Load hCaptcha test scene
	var hcaptcha_scene = load("res://view/hud/hcaptcha/hcaptcha_test.tscn")
	if not hcaptcha_scene:
		push_error("Title: Failed to load hCaptcha test scene!")
		return

	# Instantiate hCaptcha test interface
	hcaptcha_test = hcaptcha_scene.instantiate()
	add_child(hcaptcha_test)

	# Connect to captcha_closed signal
	if hcaptcha_test.has_signal("captcha_closed"):
		hcaptcha_test.captcha_closed.connect(_on_captcha_closed)

	print("[Title] hCaptcha test interface loaded")

## Handle captcha closed - called when user closes the hCaptcha test interface
func _on_captcha_closed(token: String) -> void:
	print("[Title] hCaptcha interface closed")

	# Display result
	if token and not token.is_empty():
		print("[Title] hCaptcha token received: ", token)
		# Store token in Cache for later use (authentication, verification, etc.)
		if Cache:
			Cache.set_value("hcaptcha_token", token)
			print("[Title] Token saved to Cache - you can retrieve it with Cache.get_value('hcaptcha_token')")
	else:
		print("[Title] No hCaptcha token received - user may not have completed the challenge")

	# Clean up reference
	hcaptcha_test = null
