# Coastal Castle City Setup (Improved)

## What's Different

Instead of forcing (0,0) to be grassland, we now **query the procedurally generated world** to find an optimal coastal location near spawn!

## How It Works

### 1. Natural Terrain Generation
- World generates completely naturally with no hardcoded tiles
- Preserves the integrity of your procedural generation algorithm
- No special cases or if-statements in terrain generation

### 2. Smart City Placement
- New `CityLocationFinder` class finds optimal locations
- Searches in a spiral pattern outward from origin
- Prioritizes **grassland tiles adjacent to water** (coastline)
- Falls back gracefully if no coast found

### 3. Structure Manager
- Manages all structures in the world
- Tracks ownership using player ULIDs
- Provides methods for spawning owned and neutral structures
- Uses optimal coastal location instead of hardcoded (0,0)

## Usage in GDScript

```gdscript
extends Node

@onready var structure_manager: StructureManager
var world_seed: int = 12345  # Your world seed
var player_ulid: PackedByteArray  # Player's ULID

func _ready():
    # Create structure manager
    structure_manager = StructureManager.new()
    add_child(structure_manager)

    # Get player ULID (from player entity or wherever you store it)
    player_ulid = PlayerManager.get_player_ulid()  # or however you access it

    # Find optimal coastal location
    var city_tile = CityLocationFinder.find_coastal_location(world_seed, 3)
    print("Found coastal city location at tile: ", city_tile)

    # Convert to world position
    var city_world_pos = CityLocationFinder.tile_to_world_pos(city_tile)
    print("World position: ", city_world_pos)

    # Spawn origin castle owned by the player
    var origin_city = structure_manager.spawn_origin_city(
        player_ulid,
        city_world_pos.x,
        city_world_pos.y
    )

    # Origin castle is automatically initialized with:
    # - Population: 5000
    # - Wealth: 75.0
    # - Reputation: 50.0
    # - Flags: CITY | CASTLE | MARKET | FORTIFIED | TRADING_POST | INHABITED

    print("Origin castle spawned at coastal location, owned by player!")
```

## Alternative: Manual Structure Creation

If you want more control, you can manually create structures:

```gdscript
# Find location
var city_tile = CityLocationFinder.find_coastal_location(world_seed, 3)
var city_pos = CityLocationFinder.tile_to_world_pos(city_tile)

# Create owned structure
var flags = StructureType.CITY | StructureType.CASTLE | StructureType.MARKET | \
            StructureType.FORTIFIED | StructureType.TRADING_POST | StructureType.INHABITED

var origin = structure_manager.create_structure(
    player_ulid,  # Owner ULID
    flags,
    city_pos.x,
    city_pos.y,
    "Origin Castle"
)
origin.set_population(5000)
origin.set_wealth(75.0)
origin.set_reputation(50.0)

# Or create neutral/unowned structures
var neutral_village = structure_manager.create_neutral_structure(
    StructureType.VILLAGE | StructureType.INHABITED,
    some_x,
    some_y,
    "Neutral Village"
)
```

## Search Parameters

The `search_radius` parameter controls how far to look:

```gdscript
# Search 1 chunk radius (32x32 tiles around origin)
var location1 = CityLocationFinder.find_coastal_location(seed, 1)

# Search 2 chunk radius (~64x64 tiles) - RECOMMENDED
var location2 = CityLocationFinder.find_coastal_location(seed, 2)

# Search 3 chunk radius (~96x96 tiles) - More thorough but slower
var location3 = CityLocationFinder.find_coastal_location(seed, 3)
```

## What Gets Found

The algorithm looks for:

1. **First priority**: Grassland tile adjacent to water (coastline)
   - Any of the 6 grassland variants
   - Must touch at least one water tile

2. **Fallback**: Any grassland tile (if no coast in search radius)

3. **Ultimate fallback**: (0, 0) if entire search area is water

## Benefits

✅ **Natural world generation** - No hardcoded tiles
✅ **Realistic placement** - Cities on coastlines make sense
✅ **Deterministic** - Same seed = same city location
✅ **Ownership tracking** - Structures are owned by players via ULID
✅ **Flexible** - Easy to add more city types later
✅ **Fast** - Spiral search finds coastal tiles quickly

## Rendering the City

Once you have the location, render the city sprite:

```gdscript
func render_city_on_map(tile_coords: Vector2i):
    # Get world position
    var world_pos = CityLocationFinder.tile_to_world_pos(tile_coords)

    # Get your city sprite from atlas (column 9 / index 8)
    var city_sprite = Sprite2D.new()
    city_sprite.texture = load("res://path/to/terrain_atlas.png")
    city_sprite.region_enabled = true
    city_sprite.region_rect = Rect2(8 * tile_width, 0, tile_width, tile_height)
    city_sprite.position = world_pos

    add_child(city_sprite)
```

## Files Changed

- ✅ [rust/src/world_gen/biomes.rs](rust/src/world_gen/biomes.rs) - **Reverted** to pure proc-gen
- ✅ [rust/src/world_gen/biomes.rs](rust/src/world_gen/biomes.rs#L155-L284) - Added `find_coastal_city_location()`
- ✅ [rust/src/world_gen/city_location.rs](rust/src/world_gen/city_location.rs) - New GDScript helper class
- ✅ [rust/src/world_gen/mod.rs](rust/src/world_gen/mod.rs) - Exports `CityLocationFinder`
- ✅ [rust/src/structures/manager.rs](rust/src/structures/manager.rs) - Structure management with ownership
- ✅ [rust/src/structures/city.rs](rust/src/structures/city.rs) - Structure data (i64 flags, ULID ownership)

## Next Steps

1. Add `StructureManager` and find coastal location on game start
2. Render city sprite at the found location (column 9 of tileset)
3. Add click detection for structures
4. Connect to `structure_info_panel` UI

The world is procedurally generated, and the city finds its perfect coastal home! 🌊🏰

