# Origin Castle City Setup

## What's Implemented

### 1. Guaranteed Grassland at (0,0)
- Modified [rust/src/world_gen/biomes.rs](rust/src/world_gen/biomes.rs:144-151)
- Tile (0, 0) is now **always** `Grassland0` regardless of noise generation
- This ensures a safe spawn point for the origin city

### 2. Structure Manager (Rust)
- New file: [rust/src/structures/manager.rs](rust/src/structures/manager.rs)
- Manages all structures in the world
- Tracks structures by ID with thread-safe storage

### 3. Origin Castle City
The origin city has these flags combined:
```rust
CITY | CASTLE | MARKET | FORTIFIED | TRADING_POST | INHABITED
```

This means it's:
- **CITY** - Major settlement
- **CASTLE** - Fortified stronghold
- **MARKET** - Trading hub
- **FORTIFIED** - Has defenses (32)
- **TRADING_POST** - Can trade (64)
- **INHABITED** - Has population (128)

Initial stats:
- **Population**: 5,000
- **Wealth**: 75.0 (out of 100)
- **Reputation**: 50.0 (friendly)
- **Name**: "Origin Castle"

## How to Use

### In Your Game Init Script (GDScript)

```gdscript
extends Node

@onready var structure_manager: StructureManager

func _ready():
    # Create the structure manager
    structure_manager = StructureManager.new()
    add_child(structure_manager)

    # Spawn the origin castle at (0, 0)
    var origin_city = structure_manager.spawn_origin_city()

    print("Origin castle spawned!")
    print("Name: ", origin_city.get_name())
    print("Type: ", origin_city.get_type_name())
    print("Population: ", origin_city.get_population())
    print("Can trade: ", origin_city.has_type(StructureType.TRADING_POST))
```

### Creating Additional Structures

```gdscript
# Create a village
var village_flags = StructureType.VILLAGE | StructureType.INHABITED
var village = structure_manager.create_structure(
    village_flags,
    500.0,  # x position
    300.0,  # y position
    "Riverside Village"
)
village.set_population(200)
village.set_wealth(30.0)

# Create a hostile castle
var enemy_flags = StructureType.CASTLE | StructureType.FORTIFIED | StructureType.HOSTILE
var enemy_castle = structure_manager.create_structure(
    enemy_flags,
    -1000.0,
    800.0,
    "Dark Fortress"
)
enemy_castle.set_reputation(-80.0)  # Very hostile
```

### Querying Structures

```gdscript
# Get structure by ID
var structure = structure_manager.get_structure(1)

# Get all structures
var all_structures = structure_manager.get_all_structures()
for s in all_structures:
    print("Structure: ", s.get_name())

# Get structures near player
var player_pos = player.global_position
var nearby = structure_manager.get_structures_near(
    player_pos.x,
    player_pos.y,
    1000.0  # radius in pixels
)

# Total count
var count = structure_manager.get_structure_count()
```

### Displaying Structure UI

```gdscript
# When player clicks a structure
func _on_structure_clicked(structure):
    if structure_info_panel:
        structure_info_panel.show_structure(structure)
```

## Tile Atlas Info

You mentioned the 9th column in your tileset. If you want to display a city sprite:

```gdscript
# In your rendering code
func draw_structure_on_map(structure: Structure):
    var pos = structure.get_position()

    # Check if it's a city
    if structure.has_type(StructureType.CITY):
        # Atlas column 9 (0-indexed = column 8)
        # Assuming 10 columns total, adjust based on your atlas
        var atlas_coords = Vector2i(8, 0)  # Column 9, row 1

        # Draw sprite at structure position
        # (Implementation depends on your rendering system)
```

## Integration Steps

1. **Add StructureManager to your main scene**
   ```gdscript
   var structure_manager = StructureManager.new()
   add_child(structure_manager)
   structure_manager.spawn_origin_city()
   ```

2. **Render the city sprite** on the map at (0, 0)
   - Use tile atlas column 9 (index 8)
   - Position at tile (0, 0) world coordinates

3. **Add click detection** for structures
   - When player clicks near (0, 0), show the structure panel
   - Use `structure_info_panel.show_structure(origin_city)`

4. **Connect action buttons** in the structure panel
   - Trade: Open trade window
   - Rest: Restore HP/EP
   - Recruit: Open recruitment
   - Defend: Since it's a friendly castle, this could be "Enter"

## File Changes Summary

- ✅ [rust/src/world_gen/biomes.rs](rust/src/world_gen/biomes.rs) - Origin always grassland
- ✅ [rust/src/structures/city.rs](rust/src/structures/city.rs) - Structure data with i64 flags
- ✅ [rust/src/structures/manager.rs](rust/src/structures/manager.rs) - New structure manager
- ✅ [rust/src/structures/mod.rs](rust/src/structures/mod.rs) - Module exports
- ✅ [rust/src/lib.rs](rust/src/lib.rs) - Added structures module
- ✅ [cat/view/hud/structure_info_panel.gd](cat/view/hud/structure_info_panel.gd) - UI panel
- ✅ [cat/core/i18n.gd](cat/core/i18n.gd) - Translations

Everything is compiled and ready to use! 🏰
