extends CanvasLayer
class_name NovelPanel

## Visual Novel Dialogue Panel (Global Singleton)
## Displays dialogue with avatar, background, speaker name, and player choices
## Supports typewriter effect and branching dialogue
##
## Usage (as global autoload):
## GlobalNovel.show_dialogue({...})
## GlobalNovel.show_dialogue_sequence([{...}, {...}])

# UI References
@onready var panel_container: PanelContainer = $PanelContainer
@onready var title_label: Label = $PanelContainer/MarginContainer/VBoxContainer/HeaderBar/TitleLabel
@onready var close_button: Button = $PanelContainer/MarginContainer/VBoxContainer/HeaderBar/CloseButton
@onready var background_image: TextureRect = $PanelContainer/MarginContainer/VBoxContainer/ContentContainer/LeftPanel/BackgroundContainer/BackgroundImage
@onready var avatar_image: TextureRect = $PanelContainer/MarginContainer/VBoxContainer/ContentContainer/LeftPanel/AvatarContainer/AvatarImage
@onready var speaker_name_label: Label = $PanelContainer/MarginContainer/VBoxContainer/ContentContainer/RightPanel/SpeakerNameLabel
@onready var dialogue_label: Label = $PanelContainer/MarginContainer/VBoxContainer/ContentContainer/RightPanel/DialogueScroll/DialogueLabel
@onready var choices_container: VBoxContainer = $PanelContainer/MarginContainer/VBoxContainer/ContentContainer/RightPanel/ChoicesContainer
@onready var choice_button_1: Button = $PanelContainer/MarginContainer/VBoxContainer/ContentContainer/RightPanel/ChoicesContainer/ChoiceButton1
@onready var choice_button_2: Button = $PanelContainer/MarginContainer/VBoxContainer/ContentContainer/RightPanel/ChoicesContainer/ChoiceButton2
@onready var choice_button_3: Button = $PanelContainer/MarginContainer/VBoxContainer/ContentContainer/RightPanel/ChoicesContainer/ChoiceButton3
@onready var choice_button_4: Button = $PanelContainer/MarginContainer/VBoxContainer/ContentContainer/RightPanel/ChoicesContainer/ChoiceButton4
@onready var continue_button: Button = $PanelContainer/MarginContainer/VBoxContainer/ContentContainer/RightPanel/ChoicesContainer/ContinueButton

# Typewriter effect
var typewriter_tween: Tween = null
var current_full_text: String = ""
var typewriter_speed: float = 0.03  # seconds per character
var typewriter_active: bool = false

# Current dialogue state
var current_dialogue: Dictionary = {}
var dialogue_queue: Array[Dictionary] = []
var choice_callbacks: Array[Callable] = []

# Signals
signal dialogue_finished()
signal choice_selected(choice_index: int)
signal panel_closed()

func _ready() -> void:
	# Start hidden
	panel_container.visible = false

	# Apply Alagard font to all text elements
	_apply_fonts()

	# Connect close button
	if close_button:
		close_button.pressed.connect(_on_close_pressed)

	# Connect choice buttons
	if choice_button_1:
		choice_button_1.pressed.connect(func(): _on_choice_selected(0))
	if choice_button_2:
		choice_button_2.pressed.connect(func(): _on_choice_selected(1))
	if choice_button_3:
		choice_button_3.pressed.connect(func(): _on_choice_selected(2))
	if choice_button_4:
		choice_button_4.pressed.connect(func(): _on_choice_selected(3))
	if continue_button:
		continue_button.pressed.connect(_on_continue_pressed)

	# Connect to language change signal
	if I18n:
		I18n.language_changed.connect(_on_language_changed)

	print("NovelPanel: Ready (Global Singleton)")

func _input(event: InputEvent) -> void:
	if not panel_container.visible:
		return

	# Close on ESC key
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			close_panel()
			get_viewport().set_input_as_handled()
		# Skip typewriter on SPACE or ENTER
		elif event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
			if typewriter_active:
				_skip_typewriter()
				get_viewport().set_input_as_handled()

## Show dialogue panel with dialogue data
## dialogue_data format:
## {
##   "title": "Chapter 1" or "ui.dialogue.title",  # Optional panel title (supports i18n keys)
##   "speaker": "Viking Captain" or "npc.viking.name",  # Speaker name (supports i18n keys)
##   "dialogue": "Welcome to our ship!" or "npc.viking.greeting",  # Dialogue text (supports i18n keys)
##   "avatar": Texture2D,  # Optional avatar image
##   "background": Texture2D,  # Optional background image
##   "choices": ["Accept", "Decline"] or ["ui.choice.accept", "ui.choice.decline"],  # Optional array of choice text (supports i18n keys)
##   "choice_callbacks": [callable1, callable2]  # Optional array of callables for choices
## }
func show_dialogue(dialogue_data: Dictionary) -> void:
	current_dialogue = dialogue_data

	# Update title (with i18n support)
	if title_label and dialogue_data.has("title"):
		title_label.text = _translate_if_key(dialogue_data["title"])
	elif title_label:
		title_label.text = I18n.translate("ui.dialogue.title") if I18n.has_key("ui.dialogue.title") else "Dialogue"

	# Update speaker name (with i18n support)
	if speaker_name_label and dialogue_data.has("speaker"):
		speaker_name_label.text = _translate_if_key(dialogue_data["speaker"])
	elif speaker_name_label:
		speaker_name_label.text = ""

	# Update avatar image
	if avatar_image and dialogue_data.has("avatar") and dialogue_data["avatar"] is Texture2D:
		avatar_image.texture = dialogue_data["avatar"]
		avatar_image.visible = true
	elif avatar_image:
		avatar_image.texture = null
		avatar_image.visible = false

	# Update background image
	if background_image and dialogue_data.has("background") and dialogue_data["background"] is Texture2D:
		background_image.texture = dialogue_data["background"]
		background_image.visible = true
	elif background_image:
		background_image.texture = null
		background_image.visible = false

	# Start typewriter for dialogue text (with i18n support)
	if dialogue_data.has("dialogue"):
		var translated_dialogue = _translate_if_key(dialogue_data["dialogue"])
		_start_typewriter(translated_dialogue)
	else:
		_start_typewriter("")

	# Setup choices (with i18n support)
	_setup_choices(dialogue_data)

	# Show panel with fade-in animation
	_show_panel_animated()

## Queue multiple dialogues to show sequentially
func show_dialogue_sequence(dialogue_array: Array[Dictionary]) -> void:
	dialogue_queue = dialogue_array.duplicate()
	if dialogue_queue.size() > 0:
		show_dialogue(dialogue_queue.pop_front())

## Close the panel
func close_panel() -> void:
	_stop_typewriter()
	_hide_panel_animated()
	panel_closed.emit()

## Apply Alagard font to all text elements
func _apply_fonts() -> void:
	var font = Cache.get_font_for_current_language()
	if not font:
		return

	if title_label:
		title_label.add_theme_font_override("font", font)
	if close_button:
		close_button.add_theme_font_override("font", font)
	if speaker_name_label:
		speaker_name_label.add_theme_font_override("font", font)
	if dialogue_label:
		dialogue_label.add_theme_font_override("font", font)
	if choice_button_1:
		choice_button_1.add_theme_font_override("font", font)
	if choice_button_2:
		choice_button_2.add_theme_font_override("font", font)
	if choice_button_3:
		choice_button_3.add_theme_font_override("font", font)
	if choice_button_4:
		choice_button_4.add_theme_font_override("font", font)
	if continue_button:
		continue_button.add_theme_font_override("font", font)

## Start typewriter effect for dialogue text
func _start_typewriter(text: String) -> void:
	_stop_typewriter()

	current_full_text = text
	typewriter_active = true

	if not dialogue_label:
		return

	# Start with empty text
	dialogue_label.text = ""

	# Create typewriter tween
	typewriter_tween = create_tween()

	# Animate each character
	for i in range(text.length() + 1):
		typewriter_tween.tween_callback(
			func():
				if dialogue_label:
					dialogue_label.text = current_full_text.substr(0, i)
		)
		if i < text.length():
			typewriter_tween.tween_interval(typewriter_speed)

	# When typewriter finishes, mark as inactive and show continue/choices
	typewriter_tween.tween_callback(
		func():
			typewriter_active = false
			_on_typewriter_finished()
	)

## Stop typewriter effect
func _stop_typewriter() -> void:
	if typewriter_tween and typewriter_tween.is_valid():
		typewriter_tween.kill()
		typewriter_tween = null
	typewriter_active = false

## Skip typewriter and show full text immediately
func _skip_typewriter() -> void:
	_stop_typewriter()
	if dialogue_label:
		dialogue_label.text = current_full_text
	_on_typewriter_finished()

## Called when typewriter finishes
func _on_typewriter_finished() -> void:
	# Show continue button or choices
	if current_dialogue.has("choices") and current_dialogue["choices"].size() > 0:
		# Choices are already visible, just ensure they're enabled
		_enable_choice_buttons(true)
	elif continue_button:
		# Show continue button if no choices
		continue_button.visible = true

	dialogue_finished.emit()

## Setup choice buttons based on dialogue data
func _setup_choices(dialogue_data: Dictionary) -> void:
	# Hide all choice buttons first
	choice_button_1.visible = false
	choice_button_2.visible = false
	choice_button_3.visible = false
	choice_button_4.visible = false
	continue_button.visible = false

	# Store callbacks
	if dialogue_data.has("choice_callbacks"):
		choice_callbacks = dialogue_data["choice_callbacks"]
	else:
		choice_callbacks = []

	# Setup choice buttons if choices exist
	if dialogue_data.has("choices") and dialogue_data["choices"].size() > 0:
		var choices: Array = dialogue_data["choices"]

		# Show and configure choice buttons (disabled until typewriter finishes, with i18n support)
		if choices.size() > 0 and choice_button_1:
			choice_button_1.text = _translate_if_key(choices[0])
			choice_button_1.visible = true
			choice_button_1.disabled = true

		if choices.size() > 1 and choice_button_2:
			choice_button_2.text = _translate_if_key(choices[1])
			choice_button_2.visible = true
			choice_button_2.disabled = true

		if choices.size() > 2 and choice_button_3:
			choice_button_3.text = _translate_if_key(choices[2])
			choice_button_3.visible = true
			choice_button_3.disabled = true

		if choices.size() > 3 and choice_button_4:
			choice_button_4.text = _translate_if_key(choices[3])
			choice_button_4.visible = true
			choice_button_4.disabled = true
	else:
		# No choices - will show continue button after typewriter
		pass

## Enable/disable choice buttons
func _enable_choice_buttons(enabled: bool) -> void:
	if choice_button_1.visible:
		choice_button_1.disabled = not enabled
	if choice_button_2.visible:
		choice_button_2.disabled = not enabled
	if choice_button_3.visible:
		choice_button_3.disabled = not enabled
	if choice_button_4.visible:
		choice_button_4.disabled = not enabled

## Show panel with fade-in animation
func _show_panel_animated() -> void:
	panel_container.visible = true
	panel_container.modulate = Color(1, 1, 1, 0)

	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(panel_container, "modulate", Color(1, 1, 1, 1), 0.3)

## Hide panel with fade-out animation
func _hide_panel_animated() -> void:
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(panel_container, "modulate", Color(1, 1, 1, 0), 0.2)
	tween.tween_callback(func(): panel_container.visible = false)

## Handle close button press
func _on_close_pressed() -> void:
	close_panel()

## Handle choice selection
func _on_choice_selected(choice_index: int) -> void:
	print("NovelPanel: Choice selected - ", choice_index)

	# Call the choice callback if it exists
	if choice_index < choice_callbacks.size() and choice_callbacks[choice_index]:
		choice_callbacks[choice_index].call()

	# Emit signal
	choice_selected.emit(choice_index)

	# Continue to next dialogue in queue if exists
	if dialogue_queue.size() > 0:
		show_dialogue(dialogue_queue.pop_front())
	else:
		close_panel()

## Handle continue button press
func _on_continue_pressed() -> void:
	# Continue to next dialogue in queue if exists
	if dialogue_queue.size() > 0:
		show_dialogue(dialogue_queue.pop_front())
	else:
		close_panel()

## Handle language changes
func _on_language_changed(_new_language: int) -> void:
	_apply_fonts()

	# Refresh current dialogue if panel is visible
	if panel_container.visible and current_dialogue:
		show_dialogue(current_dialogue)

## Helper function to translate text if it's an i18n key
## If the text is an i18n key (e.g., "npc.viking.greeting"), translate it
## Otherwise, return the text as-is
func _translate_if_key(text: String) -> String:
	if text.is_empty():
		return text

	# Check if I18n system exists and has this key
	if I18n and I18n.has_key(text):
		return I18n.translate(text)

	# Not a key, return original text
	return text
