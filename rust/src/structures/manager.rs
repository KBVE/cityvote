use godot::prelude::*;
use super::{Structure, StructureFlags};
use std::sync::Arc;
use parking_lot::RwLock;

/// Structure manager - handles spawning and tracking structures in the world
#[derive(GodotClass)]
#[class(init, base=Node)]
pub struct StructureManager {
    base: Base<Node>,

    /// Stores all structures by ID
    structures: Arc<RwLock<Vec<Gd<Structure>>>>,

    /// Next ID to assign
    next_id: Arc<RwLock<i64>>,
}

#[godot_api]
impl StructureManager {
    /// Spawn the origin city owned by the player
    /// This is called during initial world setup
    #[func]
    pub fn spawn_origin_city(&mut self, player_ulid: PackedByteArray, x: f32, y: f32) -> Gd<Structure> {
        let id = self.get_next_id();

        // Create a fortified city with market at origin
        let flags = StructureFlags::CITY.bits()
            | StructureFlags::CASTLE.bits()
            | StructureFlags::MARKET.bits()
            | StructureFlags::FORTIFIED.bits()
            | StructureFlags::TRADING_POST.bits()
            | StructureFlags::INHABITED.bits();

        let mut structure = Structure::new_structure(
            id,
            player_ulid.clone(),
            flags,
            x,
            y,
            "Origin Castle".into()
        );

        // Set initial stats for origin city
        structure.bind_mut().set_population(5000);
        structure.bind_mut().set_wealth(75.0);
        structure.bind_mut().set_reputation(50.0);  // Friendly starting rep

        // Store and return
        self.add_structure(structure.clone());

        godot_print!("StructureManager: Spawned origin castle at ({}, {}) with ID {} for player", x, y, id);

        structure
    }

    /// Create a new structure owned by a player
    #[func]
    pub fn create_structure(
        &mut self,
        owner_ulid: PackedByteArray,
        structure_type: i64,
        x: f32,
        y: f32,
        name: GString
    ) -> Gd<Structure> {
        let id = self.get_next_id();
        let structure = Structure::new_structure(id, owner_ulid, structure_type, x, y, name);
        self.add_structure(structure.clone());
        structure
    }

    /// Create a neutral/unowned structure
    #[func]
    pub fn create_neutral_structure(
        &mut self,
        structure_type: i64,
        x: f32,
        y: f32,
        name: GString
    ) -> Gd<Structure> {
        let id = self.get_next_id();
        let structure = Structure::new_neutral_structure(id, structure_type, x, y, name);
        self.add_structure(structure.clone());
        structure
    }

    /// Get a structure by ID
    #[func]
    pub fn get_structure(&self, id: i64) -> Option<Gd<Structure>> {
        let structures = self.structures.read();
        structures.iter()
            .find(|s| s.bind().get_id() == id)
            .cloned()
    }

    /// Get all structures
    #[func]
    pub fn get_all_structures(&self) -> VariantArray {
        let structures = self.structures.read();
        let mut array = VariantArray::new();
        for structure in structures.iter() {
            array.push(&structure.to_variant());
        }
        array
    }

    /// Get structures near a position
    #[func]
    pub fn get_structures_near(&self, x: f32, y: f32, radius: f32) -> VariantArray {
        let structures = self.structures.read();
        let mut array = VariantArray::new();
        let radius_sq = radius * radius;

        for structure in structures.iter() {
            let pos = structure.bind().get_position();
            let dx = pos.x - x;
            let dy = pos.y - y;
            let dist_sq = dx * dx + dy * dy;

            if dist_sq <= radius_sq {
                array.push(&structure.to_variant());
            }
        }

        array
    }

    /// Remove a structure by ID
    #[func]
    pub fn remove_structure(&mut self, id: i64) -> bool {
        let mut structures = self.structures.write();
        if let Some(index) = structures.iter().position(|s| s.bind().get_id() == id) {
            structures.remove(index);
            godot_print!("StructureManager: Removed structure ID {}", id);
            true
        } else {
            false
        }
    }

    /// Get total number of structures
    #[func]
    pub fn get_structure_count(&self) -> i64 {
        self.structures.read().len() as i64
    }

    /// Internal: Add a structure to the manager
    fn add_structure(&mut self, structure: Gd<Structure>) {
        let mut structures = self.structures.write();
        structures.push(structure);
    }

    /// Internal: Get next unique ID
    fn get_next_id(&self) -> i64 {
        let mut next_id = self.next_id.write();
        let id = *next_id;
        *next_id += 1;
        id
    }
}

#[godot_api]
impl INode for StructureManager {
    fn ready(&mut self) {
        godot_print!("StructureManager ready!");
    }
}
