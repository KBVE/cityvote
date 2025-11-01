# Structures System

## Overview

The structures system provides cities, villages, castles, ruins, markets, and other interactive locations in the game world. All structure data is managed on the Rust side for performance and consistency.

## Structure Types (Bitwise Flags)

Structures use bitwise flags, allowing them to have multiple properties:

### Base Types
- `CITY` (1) - Large settlement
- `VILLAGE` (2) - Small settlement
- `CASTLE` (4) - Fortified stronghold
- `RUINS` (8) - Abandoned structures
- `MARKET` (16) - Trading post

### Properties
- `FORTIFIED` (32) - Has defenses
- `TRADING_POST` (64) - Can trade
- `INHABITED` (128) - Has population
- `HOSTILE` (256) - Attacks on sight
- `ABANDONED` (512) - No longer active

### Examples

You can combine flags to create complex structures:

```gdscript
# Fortified trading city
var city_flags = StructureType.CITY | StructureType.FORTIFIED | StructureType.TRADING_POST | StructureType.INHABITED

# Abandoned village ruins
var ruins_flags = StructureType.VILLAGE | StructureType.RUINS | StructureType.ABANDONED

# Hostile castle
var castle_flags = StructureType.CASTLE | StructureType.FORTIFIED | StructureType.HOSTILE
```

## Rust Implementation

### Location
- `/rust/src/structures/city.rs` - Structure definitions and logic
- Not yet added to `mod.rs` (to be integrated later)

### Structure Class

The `Structure` class provides all structure data and functionality:

```rust
// Create a new structure
let structure = Structure::new_structure(
    id,           // i64: Unique ID
    structure_type, // i64: Bitwise flags (matches GDScript int)
    x, y,         // f32: World position
    name          // GString: Structure name
);

// Core properties
structure.get_id()
structure.get_position()  // Vector2
structure.get_name()
structure.get_structure_type()  // Returns flags

// Gameplay stats
structure.get_population()
structure.get_wealth()  // 0-100
structure.get_reputation()  // -100 to 100
structure.is_structure_active()

// Modifiers
structure.modify_population(delta)
structure.modify_wealth(delta)
structure.modify_reputation(delta)

// Utility methods
structure.get_description()  // Returns contextual description
structure.can_interact()  // Based on reputation
structure.get_trade_modifier()  // Price modifier based on reputation
structure.has_type(flag)  // Check if has specific flag
structure.add_type(flag)  // Add a flag
structure.remove_type(flag)  // Remove a flag
```

## GDScript UI

### StructureInfoPanel

Location: `/cat/view/hud/structure_info_panel.gd`

The panel displays structure information when a structure is clicked:

```gdscript
# Get reference to panel (add to scene first)
@onready var structure_panel = $StructureInfoPanel

# Show structure info
structure_panel.show_structure(structure)

# Close panel
structure_panel.close_panel()
```

The panel automatically displays:
- Structure name and type
- Description (context-aware based on type and stats)
- Stats (position, status, population, wealth, reputation)
- Action buttons (trade, rest, recruit, attack/defend)
- Progress bars for wealth and reputation

### Integration Example

```gdscript
func _on_structure_clicked(structure):
    # structure is a Rust Structure object
    if structure_info_panel:
        structure_info_panel.show_structure(structure)
```

## Translations

All structure UI text is translated via the I18n system:

- `structure.type` - Type label
- `structure.position` - Position label
- `structure.status` - Status label
- `structure.active` / `structure.inactive` - Status values
- `structure.population` - Population stat
- `structure.wealth` - Wealth stat
- `structure.reputation` - Reputation stat
- `structure.trade_modifier` - Trade modifier stat
- `structure.action.trade` - Trade button
- `structure.action.rest` - Rest button
- `structure.action.recruit` - Recruit button
- `structure.action.attack` - Attack button
- `structure.action.defend` - Defend button (for hostile structures)

Languages supported: English, Japanese, Chinese, Hindi, Spanish

## Action Buttons

The panel shows context-aware action buttons:

- **Trade** - Only shown for `TRADING_POST` structures when `can_interact()` is true
- **Rest** - Only shown for `INHABITED` structures when `can_interact()` is true
- **Recruit** - Only shown for `CITY` or `VILLAGE` structures when `can_interact()` is true
- **Attack/Defend** - Always shown, text changes based on `HOSTILE` flag

Button handlers are stubs - implement the actual functionality:
- `_on_trade_pressed()` - Open trade window
- `_on_rest_pressed()` - Restore player health/energy
- `_on_recruit_pressed()` - Open recruitment window
- `_on_attack_pressed()` - Initiate combat

## Next Steps

To integrate structures into the game:

1. Add `pub mod city;` to `/rust/src/structures/mod.rs`
2. Add `pub mod structures;` to `/rust/src/lib.rs`
3. Create a structure manager to spawn and track structures
4. Add structure rendering/sprites
5. Implement click detection on structures
6. Connect to `StructureInfoPanel.show_structure()`
7. Implement action button handlers
8. Add structure generation to world generation system
9. Implement saving/loading structure data
10. Add structure-specific gameplay (trading, recruiting, etc.)

## Design Notes

- **Bitwise flags** allow flexible structure combinations without inheritance
- **Rust-side data** ensures consistency and performance
- **GDScript UI** provides flexibility for visual design
- **Reputation system** affects interactions and prices
- **Wealth system** affects structure quality and available goods
- **Population** can grow/shrink based on player actions
- **Active/inactive state** allows dynamic world changes
