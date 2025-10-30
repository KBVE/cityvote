# Global Pointer UI System

A reusable attention-drawing UI system that can point to any location or node in the game.

## Features

- ✨ Animated arrow with bobbing motion
- 🔄 Pulsing circle effect
- 📝 Optional text label
- 🎯 Multiple follow modes (world, screen, node)
- 🎨 Customizable colors
- 🌍 Singleton pattern - accessible from anywhere

## Usage

### Basic Examples

```gdscript
# Point to a world position (follows camera movement)
GlobalPointer.point_to_world_position(Vector2(100, 200), "Click here!")

# Point to a screen position (UI space)
GlobalPointer.point_to_screen_position(Vector2(640, 360), "Important!")

# Point to a node (follows as node moves)
GlobalPointer.point_to_node(my_button, "Check this out!")

# Hide the pointer
GlobalPointer.hide_pointer()
```

### Advanced Usage

```gdscript
# Change pointer color (e.g., red for danger)
GlobalPointer.set_pointer_color(Color(1.0, 0.2, 0.2, 1.0))

# Update text while visible
GlobalPointer.set_pointer_text("New message!")

# Point without text
GlobalPointer.point_to_world_position(target_pos)
```

### Tutorial Example

```gdscript
# Show pointer at mulligan button
func show_mulligan_tutorial():
    var mulligan_button = get_node("HandContainer/MulliganButton")
    GlobalPointer.point_to_node(mulligan_button, "Use this to redraw your hand!")

    # Wait 5 seconds, then hide
    await get_tree().create_timer(5.0).timeout
    GlobalPointer.hide_pointer()
```

### Highlight Entity Example

```gdscript
# Point to an NPC on the map
func highlight_enemy(enemy: Node2D):
    GlobalPointer.set_pointer_color(Color(1.0, 0.3, 0.3, 1.0))  # Red
    GlobalPointer.point_to_node(enemy, "Attack this target!")
```

### Combo Tutorial Example

```gdscript
# Point to card placement area
func show_combo_tutorial():
    var card_placement_pos = hex_map.tile_map.map_to_local(Vector2i(30, 20))
    GlobalPointer.point_to_world_position(card_placement_pos, "Place cards here for combos!")
```

## Properties

### Visual Settings (can be modified in script)

- `arrow_color`: Color of the arrow (default: golden yellow)
- `pulse_speed`: Speed of pulsing animation (default: 2.0)
- `pulse_scale_min/max`: Min/max scale of pulse effect
- `bob_amount`: Up/down bobbing distance in pixels (default: 10.0)
- `bob_speed`: Speed of bobbing animation (default: 3.0)

## Follow Modes

### `FollowMode.NONE`
Static position, no updates

### `FollowMode.SCREEN`
Screen space position (UI), doesn't follow camera movement

### `FollowMode.WORLD`
World space position, follows camera as it moves

### `FollowMode.NODE`
Follows a specific node's position automatically

## Implementation Details

- Added as **CanvasLayer** with layer 100 for top rendering
- **z_index: 1000** ensures it renders above everything
- Uses **Polygon2D** for the arrow shape
- **ColorRect** for the pulsing circle effect
- Processes every frame when visible to update animations

## Architecture

```
GlobalPointerUI (CanvasLayer)
  └── PointerContainer (Control)
      ├── Arrow (Polygon2D) - Animated arrow pointing down
      ├── PulseCircle (ColorRect) - Pulsing attention circle
      └── Label (Label) - Optional text above arrow
```

## Integration

The pointer is registered as a global autoload in `project.godot`:

```
GlobalPointer="*res://view/hud/pointer/global_pointer_ui.tscn"
```

This means it's always available and can be accessed from any script without instantiation.

## Future Enhancements

Potential additions:
- Multiple pointer colors/styles (warning, info, success)
- Curved arrow pointing from side instead of above
- Click-to-dismiss functionality
- Sequential pointer chain for multi-step tutorials
- Fade in/out animations
- Sound effects on show/hide
