# Novel Panel System

A visual novel-style dialogue system for AFK, featuring typewriter effects, player choices, and customizable avatars and backgrounds.

**Global Singleton:** Available as `GlobalNovel` autoload - reused throughout the game!

## Quick Start

```gdscript
# Show a test dialogue anywhere in your code:
GlobalNovel.show_dialogue_sequence(DialogueData.Examples.test_dialogue())

# Or create your own with plain text:
GlobalNovel.show_dialogue({
    "speaker": "Viking Captain",
    "dialogue": "Welcome aboard!",
    "choices": ["Join crew", "Decline"],
    "choice_callbacks": [
        func(): print("Joined!"),
        func(): print("Declined!")
    ]
})

# Or use i18n keys for translation:
GlobalNovel.show_dialogue({
    "speaker": "npc.viking.name",           # Will translate to Viking name
    "dialogue": "npc.viking.greeting",      # Will translate to greeting text
    "choices": ["ui.choice.accept", "ui.choice.decline"]  # Will translate choices
})
```

## Features

- **Global Singleton**: Single reusable panel accessed via `GlobalNovel`
- **Typewriter Effect**: Dialogue text appears character-by-character with smooth animation
- **Player Choices**: Support for up to 4 branching dialogue choices
- **Avatar Display**: Show character portraits during dialogue
- **Background Images**: Custom background images for different scenes
- **Dialogue Sequences**: Chain multiple dialogues together
- **Keyboard Controls**:
  - `ESC` to close panel
  - `SPACE` or `ENTER` to skip typewriter effect
- **Fade Animations**: Smooth fade-in/fade-out transitions
- **i18n Support**: All text supports internationalization via I18n system
- **Alagard Font**: Consistent pixel-art font styling

## File Structure

```
view/novel/
├── novel_panel.tscn       # Main panel scene (CanvasLayer autoload)
├── novel_panel.gd         # Panel script with logic
├── dialogue_data.gd       # Helper class for creating dialogue
└── README.md              # This file
```

## Usage

### Basic Usage (Global Singleton)

The panel is available globally as `GlobalNovel` - no need to instantiate!

1. **Show a simple dialogue**:
```gdscript
GlobalNovel.show_dialogue({
    "speaker": "Viking Captain",
    "dialogue": "Welcome aboard!",
    "title": "Greeting"
})
```

2. **Show dialogue with choices**:
```gdscript
GlobalNovel.show_dialogue({
    "speaker": "Merchant",
    "dialogue": "Would you like to trade?",
    "choices": ["Yes", "No", "Maybe later"],
    "choice_callbacks": [
        func(): print("Player chose Yes"),
        func(): print("Player chose No"),
        func(): print("Player chose Maybe later")
    ]
})
```

### Using DialogueData Helper

The `DialogueData` class provides convenient static methods:

```gdscript
# Simple dialogue
var dialogue = DialogueData.create_dialogue(
    "Jezza",
    "Hello, traveler!",
    "Jezza's Greeting"
)
GlobalNovel.show_dialogue(dialogue)

# Dialogue with choices
var choice_dialogue = DialogueData.create_choice_dialogue(
    "Elder",
    "Will you help us?",
    ["Yes", "No"],
    [
        func(): _accept_quest(),
        func(): _decline_quest()
    ],
    "Quest Offer"
)
GlobalNovel.show_dialogue(choice_dialogue)
```

### Dialogue Sequences

Chain multiple dialogues together:

```gdscript
var sequence = [
    DialogueData.create_dialogue("Guide", "Welcome!"),
    DialogueData.create_dialogue("Guide", "Let me explain..."),
    DialogueData.create_choice_dialogue("Guide", "Ready?", ["Yes", "No"])
]
GlobalNovel.show_dialogue_sequence(sequence)
```

### Using Example Dialogues

Pre-made dialogue sequences are available in `DialogueData.Examples`:

```gdscript
# Viking encounter
GlobalNovel.show_dialogue_sequence(
    DialogueData.Examples.viking_encounter()
)

# Jezza greeting
GlobalNovel.show_dialogue_sequence(
    DialogueData.Examples.jezza_greeting()
)

# Tutorial
GlobalNovel.show_dialogue_sequence(
    DialogueData.Examples.tutorial_welcome()
)

# Test dialogue
GlobalNovel.show_dialogue_sequence(
    DialogueData.Examples.test_dialogue()
)
```

### Adding Avatar and Background Images

```gdscript
var avatar_texture = load("res://assets/portraits/viking.png")
var bg_texture = load("res://assets/backgrounds/ship.png")

GlobalNovel.show_dialogue({
    "speaker": "Viking Captain",
    "dialogue": "Join my crew!",
    "avatar": avatar_texture,
    "background": bg_texture
})
```

### Using i18n for Translations

All text fields support both plain text and i18n keys. The system automatically detects if a string is an i18n key and translates it:

```gdscript
# Example: Add dialogue translations to i18n.gd
# In your i18n.gd translations dictionary:
"npc.viking.name": {
    Language.ENGLISH: "Viking Captain",
    Language.JAPANESE: "バイキング隊長",
    Language.SPANISH: "Capitán Vikingo"
},
"npc.viking.greeting": {
    Language.ENGLISH: "Welcome aboard my ship, traveler!",
    Language.JAPANESE: "私の船へようこそ、旅人よ！",
    Language.SPANISH: "¡Bienvenido a mi barco, viajero!"
},
"ui.choice.accept": {
    Language.ENGLISH: "Accept",
    Language.JAPANESE: "受け入れる",
    Language.SPANISH: "Aceptar"
},
"ui.choice.decline": {
    Language.ENGLISH: "Decline",
    Language.JAPANESE: "断る",
    Language.SPANISH: "Rechazar"
}

# Then use the keys in your dialogue:
GlobalNovel.show_dialogue({
    "speaker": "npc.viking.name",        # Auto-translates
    "dialogue": "npc.viking.greeting",   # Auto-translates
    "choices": ["ui.choice.accept", "ui.choice.decline"]  # Auto-translates
})
```

**Benefits:**
- Dialogue automatically switches language when player changes language
- No need to manually call `I18n.translate()`
- Can mix plain text and i18n keys (useful for testing)
- Panel refreshes automatically when language changes

## Dialogue Dictionary Format

```gdscript
{
    "title": String,           # Optional - Panel title (plain text or i18n key)
    "speaker": String,         # Speaker name (plain text or i18n key)
    "dialogue": String,        # Dialogue text (plain text or i18n key)
    "avatar": Texture2D,       # Optional - Character portrait
    "background": Texture2D,   # Optional - Background image
    "choices": Array[String],  # Optional - Array of choice texts (plain text or i18n keys, max 4)
    "choice_callbacks": Array[Callable]  # Optional - Callbacks for each choice
}
```

**Note:** All string fields (`title`, `speaker`, `dialogue`, `choices`) support both plain text and i18n translation keys. The system automatically detects and translates i18n keys.

## Signals

```gdscript
signal dialogue_finished()            # Emitted when typewriter finishes
signal choice_selected(choice_index)  # Emitted when player selects a choice
signal panel_closed()                 # Emitted when panel closes
```

### Connecting to Signals

```gdscript
GlobalNovel.choice_selected.connect(_on_choice_selected)
GlobalNovel.dialogue_finished.connect(_on_dialogue_finished)
GlobalNovel.panel_closed.connect(_on_panel_closed)

func _on_choice_selected(choice_index: int) -> void:
    print("Player selected choice: ", choice_index)

func _on_dialogue_finished() -> void:
    print("Dialogue typewriter finished")

func _on_panel_closed() -> void:
    print("Panel was closed")
```

## Customization

### Typewriter Speed

Adjust the typewriter speed in `novel_panel.gd`:
```gdscript
typewriter_speed = 0.03  # seconds per character (default)
typewriter_speed = 0.05  # slower
typewriter_speed = 0.01  # faster
```

### Styling

The panel uses a golden border matching the game's visual style. To customize:
- Edit `novel_panel.tscn` StyleBoxFlat resources
- Modify colors in the scene file
- Adjust margins, padding, and sizes

### Panel Size

Default size: 980x620 pixels (larger than stats panel)
- Position: offset_left = 150, offset_top = 50
- Can be adjusted in the `.tscn` file or at runtime

## Example Integration

Here's a complete example of integrating dialogue into an entity interaction:

```gdscript
# In your entity script (e.g., viking.gd)
func _on_entity_clicked() -> void:
    # Connect to choice signal (only once)
    if not GlobalNovel.choice_selected.is_connected(_on_dialogue_choice):
        GlobalNovel.choice_selected.connect(_on_dialogue_choice)

    # Show viking dialogue using the global singleton
    GlobalNovel.show_dialogue_sequence(
        DialogueData.Examples.viking_encounter()
    )

func _on_dialogue_choice(choice_index: int) -> void:
    match choice_index:
        0:  # Join crew
            print("Player joined the viking crew")
        1:  # Pay tribute
            ResourceLedger.add(ResourceLedger.R.GOLD, -50)
            print("Player paid 50 gold tribute")
        2:  # Fight
            _start_combat()
        3:  # Flee
            print("Player fled from vikings")

    # Disconnect after handling choice to avoid memory leaks
    if GlobalNovel.choice_selected.is_connected(_on_dialogue_choice):
        GlobalNovel.choice_selected.disconnect(_on_dialogue_choice)
```

## Tips

- Keep dialogue text concise for better readability
- Use sequences to break up long exposition
- Provide meaningful choices that affect gameplay
- Use avatars and backgrounds to enhance immersion
- Test dialogue with different typewriter speeds
- Consider adding sound effects for typewriter and choices (future enhancement)
