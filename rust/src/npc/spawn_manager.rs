use godot::prelude::*;
use super::entity::{EntityData, ENTITY_DATA};
use super::terrain_cache::{self, TerrainType as CacheTerrainType};
use super::entity::TerrainType as EntityTerrainType;

type HexCoord = (i32, i32);

/// Result of a spawn attempt
#[derive(Debug, Clone)]
pub struct SpawnResult {
    pub ulid: Vec<u8>,
    pub entity_type: String,
    pub position: HexCoord,
    pub terrain_type: CacheTerrainType,
    pub success: bool,
    pub error_message: String,
}

/// Validate if a location is suitable for spawning
fn is_valid_spawn_location(pos: HexCoord, terrain_type: CacheTerrainType) -> bool {
    // Check terrain matches
    let terrain = terrain_cache::get_terrain(pos.0, pos.1);
    if terrain != terrain_type {
        return false;
    }

    // Check not occupied by another entity
    let occupied = ENTITY_DATA.iter().any(|entry| {
        entry.value().position == pos
    });

    !occupied
}

/// Calculate hex distance between two coordinates
fn hex_distance(a: HexCoord, b: HexCoord) -> f32 {
    let dq = (a.0 - b.0).abs() as f32;
    let dr = (a.1 - b.1).abs() as f32;
    let ds = (a.0 + a.1 - b.0 - b.1).abs() as f32;
    ((dq + dr + ds) / 2.0).max(dq.max(dr))
}

/// Find a valid spawn location near a preferred position
fn find_nearby_spawn_location(
    preferred: HexCoord,
    terrain_type: CacheTerrainType,
    search_radius: i32,
) -> Option<HexCoord> {
    // Search in expanding rings around preferred location
    for distance in 0..=search_radius {
        for dx in -distance..=distance {
            for dy in -distance..=distance {
                let candidate = (preferred.0 + dx, preferred.1 + dy);

                // Check if within radius (hex distance)
                if hex_distance(preferred, candidate) > distance as f32 {
                    continue;
                }

                if is_valid_spawn_location(candidate, terrain_type) {
                    return Some(candidate);
                }
            }
        }
    }

    None
}

/// Find a random valid spawn location in the world
fn find_random_spawn_location(
    center: HexCoord,
    terrain_type: CacheTerrainType,
    search_radius: i32,
) -> Option<HexCoord> {
    use rand::Rng;
    let mut rng = rand::thread_rng();
    let mut valid_locations = Vec::new();

    // Search in area around center
    for dx in -search_radius..=search_radius {
        for dy in -search_radius..=search_radius {
            let candidate = (center.0 + dx, center.1 + dy);

            if is_valid_spawn_location(candidate, terrain_type) {
                valid_locations.push(candidate);
            }
        }
    }

    if valid_locations.is_empty() {
        None
    } else {
        let idx = rng.gen_range(0..valid_locations.len());
        Some(valid_locations[idx])
    }
}

/// Main spawn function - creates entity in Rust and returns spawn info
pub fn spawn_entity(
    entity_type: String,
    terrain_type: CacheTerrainType,
    preferred_location: Option<HexCoord>,
    search_radius: i32,
) -> SpawnResult {
    godot_print!("spawn_entity: type={}, terrain={:?}, preferred={:?}, radius={}",
        entity_type, terrain_type, preferred_location, search_radius);

    // Find valid spawn location
    let spawn_pos = if let Some(preferred) = preferred_location {
        // Try preferred location first
        if is_valid_spawn_location(preferred, terrain_type) {
            godot_print!("  -> Using preferred location: {:?}", preferred);
            Some(preferred)
        } else {
            // Find nearby valid location
            godot_print!("  -> Preferred location invalid, searching nearby...");
            find_nearby_spawn_location(preferred, terrain_type, search_radius)
        }
    } else {
        // Find random valid location around world origin
        godot_print!("  -> No preferred location, searching random...");
        find_random_spawn_location((0, 0), terrain_type, search_radius)
    };

    let Some(position) = spawn_pos else {
        godot_error!("spawn_entity: Failed to find valid spawn location for {} (terrain={:?})", entity_type, terrain_type);
        return SpawnResult {
            ulid: vec![],
            entity_type,
            position: (0, 0),
            terrain_type,
            success: false,
            error_message: "No valid spawn location found".to_string(),
        };
    };

    // Generate ULID for entity
    // Note: We skip the paranoid re-check here because with the worker thread,
    // there's a race between queueing insertion and checking occupancy.
    // The initial location search already validated the position.
    let ulid_obj = ulid::Ulid::new();
    let ulid = ulid_obj.to_bytes().to_vec();

    // Convert CacheTerrainType to EntityTerrainType
    let entity_terrain_type = match terrain_type {
        CacheTerrainType::Water => EntityTerrainType::Water,
        CacheTerrainType::Land => EntityTerrainType::Land,
        CacheTerrainType::Obstacle => {
            godot_error!("spawn_entity: Cannot spawn on Obstacle terrain!");
            return SpawnResult {
                ulid: vec![],
                entity_type,
                position,
                terrain_type,
                success: false,
                error_message: "Cannot spawn on obstacle terrain".to_string(),
            };
        }
    };

    // Create entity data in Rust using the proper constructor
    let entity_data = EntityData::new(
        ulid.clone(),
        position,
        entity_terrain_type,
        entity_type.clone(),
    );

    // Queue entity insertion (uses worker thread for thread-safe writes)
    super::entity_worker::queue_insert_entity(ulid.clone(), entity_data);

    godot_print!("spawn_entity: SUCCESS - Spawned {} at {:?} (ulid={:02x}{:02x}...)",
        entity_type, position, ulid[0], ulid[1]);

    SpawnResult {
        ulid,
        entity_type,
        position,
        terrain_type,
        success: true,
        error_message: String::new(),
    }
}

// ============================================================================
// GODOT BRIDGE
// ============================================================================

#[derive(GodotClass)]
#[class(base=Node)]
pub struct EntitySpawnBridge {
    base: Base<Node>,
}

#[godot_api]
impl INode for EntitySpawnBridge {
    fn init(base: Base<Node>) -> Self {
        godot_print!("EntitySpawnBridge initialized!");
        Self { base }
    }
}

#[godot_api]
impl EntitySpawnBridge {
    /// Spawn an entity and return spawn information
    ///
    /// # Arguments
    /// * `entity_type` - Type of entity to spawn ("viking", "jezza", etc.)
    /// * `terrain_type_int` - 0=Water, 1=Land
    /// * `preferred_q` - Optional preferred Q coordinate (use -999999 for none)
    /// * `preferred_r` - Optional preferred R coordinate (use -999999 for none)
    /// * `search_radius` - Radius to search for valid spawn location
    ///
    /// # Returns
    /// Dictionary with:
    /// - success: bool
    /// - ulid: PackedByteArray
    /// - position_q: int
    /// - position_r: int
    /// - terrain_type: int
    /// - error_message: String
    #[func]
    pub fn spawn_entity(
        &self,
        entity_type: GString,
        terrain_type_int: i32,
        preferred_q: i32,
        preferred_r: i32,
        search_radius: i32,
    ) -> Dictionary {
        let entity_type_str = entity_type.to_string();

        let terrain_type = match terrain_type_int {
            0 => CacheTerrainType::Water,
            1 => CacheTerrainType::Land,
            _ => {
                godot_error!("Invalid terrain_type: {}", terrain_type_int);
                let mut result = Dictionary::new();
                result.set("success", false);
                result.set("error_message", "Invalid terrain type");
                return result;
            }
        };

        let preferred_location = if preferred_q != -999999 && preferred_r != -999999 {
            Some((preferred_q, preferred_r))
        } else {
            None
        };

        let spawn_result = spawn_entity(
            entity_type_str,
            terrain_type,
            preferred_location,
            search_radius,
        );

        // Convert actual terrain type back to int for GDScript
        let actual_terrain_int = match spawn_result.terrain_type {
            CacheTerrainType::Water => 0,
            CacheTerrainType::Land => 1,
            CacheTerrainType::Obstacle => 2,
        };

        let mut result = Dictionary::new();
        result.set("success", spawn_result.success);
        result.set("ulid", PackedByteArray::from(spawn_result.ulid.as_slice()));
        result.set("entity_type", spawn_result.entity_type.clone());
        result.set("position_q", spawn_result.position.0);
        result.set("position_r", spawn_result.position.1);
        result.set("terrain_type", actual_terrain_int);  // Return ACTUAL terrain found, not requested
        result.set("error_message", spawn_result.error_message);

        result
    }

    /// Check if a location is valid for spawning
    #[func]
    pub fn is_valid_spawn_location(&self, q: i32, r: i32, terrain_type_int: i32) -> bool {
        let terrain_type = match terrain_type_int {
            0 => CacheTerrainType::Water,
            1 => CacheTerrainType::Land,
            _ => return false,
        };

        is_valid_spawn_location((q, r), terrain_type)
    }
}
