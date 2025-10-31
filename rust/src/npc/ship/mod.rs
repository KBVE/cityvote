pub mod pathfinding;

use godot::prelude::*;
use crate::npc::ship::pathfinding::*;

/// Bridge between GDScript and Rust pathfinding
#[derive(GodotClass)]
#[class(base=Node)]
pub struct ShipPathfindingBridge {
    base: Base<Node>,
}

#[godot_api]
impl INode for ShipPathfindingBridge {
    fn init(base: Base<Node>) -> Self {
        godot_print!("ShipPathfindingBridge initialized!");
        Self { base }
    }

    fn ready(&mut self) {
        godot_print!("ShipPathfindingBridge ready!");
        self.base_mut().set_process(true);
    }

    fn process(&mut self, _delta: f64) {
        // Poll for pathfinding results every frame
        while let Some(result) = pathfinding::get_result() {
            // Convert path to GDScript array
            let mut path_array = Array::new();
            for (q, r) in result.path {
                let mut coord = Dictionary::new();
                coord.set("q", q);
                coord.set("r", r);
                path_array.push(&coord);  // Push by reference
            }

            // Convert ULID Vec<u8> to PackedByteArray
            let ship_ulid = PackedByteArray::from(&result.ship_ulid[..]);

            // Emit signal with result
            self.base_mut().emit_signal(
                "path_found",
                &[
                    ship_ulid.to_variant(),
                    path_array.to_variant(),
                    result.success.to_variant(),
                    result.cost.to_variant(),
                ]
            );
        }
    }
}

#[godot_api]
impl ShipPathfindingBridge {
    /// Signal emitted when path is found
    #[signal]
    fn path_found(ship_ulid: PackedByteArray, path: Array<Dictionary>, success: bool, cost: f32);

    /// Initialize map cache with full tile data
    #[func]
    fn init_map(&mut self, tiles: Array<Dictionary>) {
        godot_print!("ShipPathfindingBridge: Initializing map with {} tiles", tiles.len());

        let mut tile_vec = Vec::new();
        for i in 0..tiles.len() {
            if let Some(dict) = tiles.get(i) {
                // Extract values from Dictionary variants
                let q: i32 = dict.get("q")
                    .and_then(|v| v.try_to::<i32>().ok())
                    .unwrap_or(0);
                let r: i32 = dict.get("r")
                    .and_then(|v| v.try_to::<i32>().ok())
                    .unwrap_or(0);
                let tile_type_str: GString = dict.get("type")
                    .and_then(|v| v.try_to::<GString>().ok())
                    .unwrap_or_else(|| "water".into());

                tile_vec.push(((q, r), tile_type_str.to_string()));
            }
        }

        pathfinding::init_map_cache(tile_vec);
    }

    /// Update specific tiles (incremental sync)
    #[func]
    fn update_tiles(&mut self, updates: Array<Dictionary>) {
        let mut update_vec = Vec::new();
        for i in 0..updates.len() {
            if let Some(dict) = updates.get(i) {
                let q: i32 = dict.get("q")
                    .and_then(|v| v.try_to::<i32>().ok())
                    .unwrap_or(0);
                let r: i32 = dict.get("r")
                    .and_then(|v| v.try_to::<i32>().ok())
                    .unwrap_or(0);
                let tile_type_str: GString = dict.get("type")
                    .and_then(|v| v.try_to::<GString>().ok())
                    .unwrap_or_else(|| "water".into());

                let tile_type = pathfinding::TerrainType::from_string(&tile_type_str.to_string());

                update_vec.push(pathfinding::TileUpdate {
                    coord: (q, r),
                    tile_type,
                });
            }
        }

        pathfinding::update_tiles(update_vec);
    }

    /// Update ship position
    #[func]
    fn update_ship_position(&mut self, ship_ulid: PackedByteArray, q: i32, r: i32) {
        let ulid_bytes: Vec<u8> = ship_ulid.to_vec();
        pathfinding::update_ship_position(ulid_bytes, (q, r));
    }

    /// Set ship state to MOVING
    #[func]
    fn set_ship_moving(&mut self, ship_ulid: PackedByteArray) {
        let ulid_bytes: Vec<u8> = ship_ulid.to_vec();
        pathfinding::set_ship_moving(ulid_bytes);
    }

    /// Set ship state to IDLE
    #[func]
    fn set_ship_idle(&mut self, ship_ulid: PackedByteArray) {
        let ulid_bytes: Vec<u8> = ship_ulid.to_vec();
        pathfinding::set_ship_idle(ulid_bytes);
    }

    /// Check if ship can accept a new path request (not already moving/pathfinding)
    #[func]
    fn can_ship_request_path(&self, ship_ulid: PackedByteArray) -> bool {
        let ulid_bytes: Vec<u8> = ship_ulid.to_vec();
        pathfinding::can_ship_accept_path_request(ulid_bytes)
    }

    /// Remove ship from tracking
    #[func]
    fn remove_ship(&mut self, ship_ulid: PackedByteArray) {
        let ulid_bytes: Vec<u8> = ship_ulid.to_vec();
        pathfinding::remove_ship(ulid_bytes);
    }

    /// Request pathfinding for a ship
    #[func]
    fn request_path(&mut self, ship_ulid: PackedByteArray, start_q: i32, start_r: i32, goal_q: i32, goal_r: i32, avoid_ships: bool) {
        let ulid_bytes: Vec<u8> = ship_ulid.to_vec();
        let request = PathRequest {
            ship_ulid: ulid_bytes,
            start: (start_q, start_r),
            goal: (goal_q, goal_r),
            avoid_ships,
        };

        pathfinding::request_path(request);
    }

    /// Start worker threads
    #[func]
    fn start_workers(&mut self, thread_count: i32) {
        pathfinding::start_workers(thread_count.max(1) as usize);
    }

    /// Stop worker threads
    #[func]
    fn stop_workers(&mut self) {
        pathfinding::stop_workers();
    }

    /// Get statistics (map size, ship count, pending requests)
    #[func]
    fn get_stats(&self) -> Dictionary {
        let (map_size, ship_count, pending) = pathfinding::get_stats();
        let mut dict = Dictionary::new();
        dict.set("map_tiles", map_size as i32);
        dict.set("ships", ship_count as i32);
        dict.set("pending_requests", pending as i32);
        dict
    }
}
