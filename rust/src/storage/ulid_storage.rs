use godot::prelude::*;
use dashmap::DashMap;
use std::sync::Arc;

/// Entity types that can be stored
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum EntityType {
    Card,
    Ship,
    NPC,
    Building,
    Resource,
    Custom(String),
}

impl EntityType {
    pub fn to_string(&self) -> String {
        match self {
            EntityType::Card => "card".to_string(),
            EntityType::Ship => "ship".to_string(),
            EntityType::NPC => "npc".to_string(),
            EntityType::Building => "building".to_string(),
            EntityType::Resource => "resource".to_string(),
            EntityType::Custom(s) => s.clone(),
        }
    }

    pub fn from_int(value: i32) -> Self {
        match value {
            0 => EntityType::Card,
            1 => EntityType::Ship,
            2 => EntityType::NPC,
            3 => EntityType::Building,
            4 => EntityType::Resource,
            _ => EntityType::Custom(format!("unknown_{}", value)),
        }
    }

    pub fn to_int(&self) -> i32 {
        match self {
            EntityType::Card => 0,
            EntityType::Ship => 1,
            EntityType::NPC => 2,
            EntityType::Building => 3,
            EntityType::Resource => 4,
            EntityType::Custom(_) => -1,
        }
    }
}

/// Entity metadata stored with ULID
#[derive(Debug, Clone)]
pub struct EntityData {
    pub entity_type: EntityType, // The entity type struct is for gd.
    pub godot_instance_id: i64,  // Godot's instance ID for the node
    pub created_at: u64,          // Timestamp when stored
    pub metadata: Dictionary,     // Additional data from GDScript
}

/// Global storage for entity ULIDs
/// Thread-safe storage using DashMap
#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct UlidStorage {
    base: Base<RefCounted>,
    storage: Arc<DashMap<Vec<u8>, EntityData>>,
}

#[godot_api]
impl IRefCounted for UlidStorage {
    fn init(base: Base<RefCounted>) -> Self {
        Self {
            base,
            storage: Arc::new(DashMap::new()),
        }
    }
}

#[godot_api]
impl UlidStorage {
    // Entity type constants for GDScript
    #[constant]
    const ENTITY_TYPE_CARD: i32 = 0;

    #[constant]
    const ENTITY_TYPE_SHIP: i32 = 1;

    #[constant]
    const ENTITY_TYPE_NPC: i32 = 2;

    #[constant]
    const ENTITY_TYPE_BUILDING: i32 = 3;

    #[constant]
    const ENTITY_TYPE_RESOURCE: i32 = 4;

    /// Store an entity with its ULID
    #[func]
    pub fn store(&mut self, ulid: PackedByteArray, entity_type: i32, instance_id: i64, metadata: Dictionary) -> bool {
        let ulid_bytes: Vec<u8> = ulid.to_vec();

        if ulid_bytes.len() != 16 {
            godot_error!("Invalid ULID: must be 16 bytes");
            return false;
        }

        let entity_type = EntityType::from_int(entity_type);
        let created_at = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .expect("Time went backwards")
            .as_millis() as u64;

        let entity_data = EntityData {
            entity_type,
            godot_instance_id: instance_id,
            created_at,
            metadata: metadata.clone(),
        };

        // Store in both instance storage and global class name storage
        self.storage.insert(ulid_bytes.clone(), entity_data.clone());
        store_entity_class(ulid_bytes, &metadata);
        true
    }

    /// Retrieve entity data by ULID
    #[func]
    pub fn get(&self, ulid: PackedByteArray) -> Variant {
        let ulid_bytes: Vec<u8> = ulid.to_vec();

        if let Some(entry) = self.storage.get(&ulid_bytes) {
            let entity_data = entry.value();

            // Return as Dictionary
            let mut dict = Dictionary::new();
            dict.set("entity_type", entity_data.entity_type.to_string());
            dict.set("instance_id", entity_data.godot_instance_id);
            dict.set("created_at", entity_data.created_at);
            dict.set("metadata", entity_data.metadata.clone());

            Variant::from(dict)
        } else {
            Variant::nil()
        }
    }

    /// Remove entity by ULID
    #[func]
    pub fn remove(&mut self, ulid: PackedByteArray) -> bool {
        let ulid_bytes: Vec<u8> = ulid.to_vec();
        // Remove from both storages
        remove_entity_class(&ulid_bytes);
        self.storage.remove(&ulid_bytes).is_some()
    }

    /// Check if ULID exists in storage
    #[func]
    pub fn has(&self, ulid: PackedByteArray) -> bool {
        let ulid_bytes: Vec<u8> = ulid.to_vec();
        self.storage.contains_key(&ulid_bytes)
    }

    /// Get all ULIDs of a specific entity type
    /// Returns concatenated PackedByteArray (each ULID is 16 bytes)
    /// Reference: https://godot-rust.github.io/book/godot-api/builtins.html#arrays-and-dictionaries
    #[func]
    pub fn get_by_type(&self, entity_type: i32) -> PackedByteArray {
        let search_type = EntityType::from_int(entity_type);
        let mut result_bytes = Vec::new();

        for entry in self.storage.iter() {
            if entry.value().entity_type == search_type {
                result_bytes.extend_from_slice(entry.key());
            }
        }

        PackedByteArray::from(&result_bytes[..])
    }

    /// Get instance ID from ULID
    #[func]
    pub fn get_instance_id(&self, ulid: PackedByteArray) -> i64 {
        let ulid_bytes: Vec<u8> = ulid.to_vec();

        if let Some(entry) = self.storage.get(&ulid_bytes) {
            entry.value().godot_instance_id
        } else {
            -1
        }
    }

    /// Update metadata for an entity
    #[func]
    pub fn update_metadata(&mut self, ulid: PackedByteArray, metadata: Dictionary) -> bool {
        let ulid_bytes: Vec<u8> = ulid.to_vec();

        if let Some(mut entry) = self.storage.get_mut(&ulid_bytes) {
            entry.value_mut().metadata = metadata;
            true
        } else {
            false
        }
    }

    /// Get total count of stored entities
    #[func]
    pub fn count(&self) -> i32 {
        self.storage.len() as i32
    }

    /// Get count of entities by type
    #[func]
    pub fn count_by_type(&self, entity_type: i32) -> i32 {
        let search_type = EntityType::from_int(entity_type);

        self.storage
            .iter()
            .filter(|entry| entry.value().entity_type == search_type)
            .count() as i32
    }

    /// Clear all stored entities
    #[func]
    pub fn clear(&mut self) {
        self.storage.clear();
    }

    /// Clear entities of a specific type
    #[func]
    pub fn clear_type(&mut self, entity_type: i32) {
        let search_type = EntityType::from_int(entity_type);

        // Collect keys to remove
        let keys_to_remove: Vec<Vec<u8>> = self.storage
            .iter()
            .filter(|entry| entry.value().entity_type == search_type)
            .map(|entry| entry.key().clone())
            .collect();

        // Remove them
        for key in keys_to_remove {
            self.storage.remove(&key);
        }
    }

    /// Get all ULIDs (for debugging)
    /// Returns concatenated PackedByteArray (each ULID is 16 bytes)
    /// Reference: https://godot-rust.github.io/book/godot-api/builtins.html#arrays-and-dictionaries
    #[func]
    pub fn get_all_ulids(&self) -> PackedByteArray {
        let mut result_bytes = Vec::new();

        for entry in self.storage.iter() {
            result_bytes.extend_from_slice(entry.key());
        }

        PackedByteArray::from(&result_bytes[..])
    }

    /// Debug: Print storage stats
    #[func]
    pub fn print_stats(&self) {
        godot_print!("=== ULID Storage Stats ===");
        godot_print!("Total entities: {}", self.storage.len());

        let mut type_counts = std::collections::HashMap::new();
        for entry in self.storage.iter() {
            let type_str = entry.value().entity_type.to_string();
            *type_counts.entry(type_str).or_insert(0) += 1;
        }

        for (entity_type, count) in type_counts {
            godot_print!("  {}: {}", entity_type, count);
        }
    }

    /// Get the internal storage reference (for Rust-side access)
    pub fn get_storage(&self) -> &Arc<DashMap<Vec<u8>, EntityData>> {
        &self.storage
    }
}

// Global storage for entity class names (thread-safe)
use once_cell::sync::Lazy;

static GLOBAL_CLASS_NAMES: Lazy<Arc<DashMap<Vec<u8>, String>>> =
    Lazy::new(|| Arc::new(DashMap::new()));

/// Get entity class name from ULID (for drop tables)
/// Returns the class name, or "default" if not found
pub fn get_entity_class(ulid: &[u8]) -> String {
    GLOBAL_CLASS_NAMES
        .get(ulid)
        .map(|entry| entry.value().clone())
        .unwrap_or_else(|| "default".to_string())
}

/// Store entity class name (called from UlidStorage.store)
pub fn store_entity_class(ulid: Vec<u8>, metadata: &Dictionary) {
    // Extract class name from metadata
    let class_name = if let Some(ship_type) = metadata.get("ship_type") {
        ship_type.try_to::<godot::builtin::GString>()
            .map(|s| s.to_string().to_lowercase())
            .unwrap_or_else(|_| "default".to_string())
    } else if let Some(npc_type) = metadata.get("npc_type") {
        npc_type.try_to::<godot::builtin::GString>()
            .map(|s| s.to_string().to_lowercase())
            .unwrap_or_else(|_| "default".to_string())
    } else {
        "default".to_string()
    };

    GLOBAL_CLASS_NAMES.insert(ulid, class_name);
}

/// Remove entity class name (called from UlidStorage.remove)
pub fn remove_entity_class(ulid: &[u8]) {
    GLOBAL_CLASS_NAMES.remove(ulid);
}
