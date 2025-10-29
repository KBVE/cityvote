use godot::prelude::*;

/// Boat/Ship state
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BoatState {
    Idle,
    Moving,
    Docked,
    Combat,
}

impl BoatState {
    pub fn to_string(&self) -> String {
        match self {
            BoatState::Idle => "idle".to_string(),
            BoatState::Moving => "moving".to_string(),
            BoatState::Docked => "docked".to_string(),
            BoatState::Combat => "combat".to_string(),
        }
    }

    pub fn from_string(s: &str) -> Self {
        match s {
            "idle" => BoatState::Idle,
            "moving" => BoatState::Moving,
            "docked" => BoatState::Docked,
            "combat" => BoatState::Combat,
            _ => BoatState::Idle,
        }
    }
}

/// Boat/Ship data structure (Rust source of truth)
#[derive(Debug, Clone)]
pub struct BoatData {
    pub ulid: Vec<u8>,              // 16-byte ULID
    pub position: (i32, i32),       // Current position (q, r) hex coords
    pub destination: Option<(i32, i32)>, // Target destination if moving
    pub state: BoatState,
    pub health: i32,
    pub max_health: i32,
    pub speed: f32,
    pub owner_id: Option<i64>,      // Godot instance ID of owner (player, AI)
    pub cargo: Vec<u8>,             // Cargo data (can be expanded)
}

impl BoatData {
    /// Create a new boat
    pub fn new(ulid: Vec<u8>, position: (i32, i32)) -> Self {
        Self {
            ulid,
            position,
            destination: None,
            state: BoatState::Idle,
            health: 100,
            max_health: 100,
            speed: 1.0,
            owner_id: None,
            cargo: Vec::new(),
        }
    }

    /// Set destination and start moving
    pub fn set_destination(&mut self, dest: (i32, i32)) {
        self.destination = Some(dest);
        self.state = BoatState::Moving;
    }

    /// Update position (called when reaching destination)
    pub fn update_position(&mut self, new_pos: (i32, i32)) {
        self.position = new_pos;

        // Check if reached destination
        if let Some(dest) = self.destination {
            if dest == new_pos {
                self.destination = None;
                self.state = BoatState::Idle;
            }
        }
    }

    /// Take damage
    pub fn take_damage(&mut self, damage: i32) {
        self.health = (self.health - damage).max(0);
    }

    /// Heal
    pub fn heal(&mut self, amount: i32) {
        self.health = (self.health + amount).min(self.max_health);
    }

    /// Check if destroyed
    pub fn is_destroyed(&self) -> bool {
        self.health <= 0
    }
}

/// Godot-exposed boat manager
#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct BoatManager {
    base: Base<RefCounted>,
}

#[godot_api]
impl IRefCounted for BoatManager {
    fn init(base: Base<RefCounted>) -> Self {
        Self { base }
    }
}

#[godot_api]
impl BoatManager {
    /// Create boat data and return as Dictionary
    #[func]
    pub fn create_boat_data(ulid: PackedByteArray, position_q: i32, position_r: i32) -> Dictionary {
        let ulid_vec: Vec<u8> = ulid.to_vec();
        let boat_data = BoatData::new(ulid_vec, (position_q, position_r));

        Self::boat_data_to_dict(&boat_data)
    }

    /// Convert BoatData to Dictionary
    fn boat_data_to_dict(boat: &BoatData) -> Dictionary {
        let mut dict = Dictionary::new();

        dict.set("ulid", PackedByteArray::from(&boat.ulid[..]));
        dict.set("position_q", boat.position.0);
        dict.set("position_r", boat.position.1);
        dict.set("state", boat.state.to_string());
        dict.set("health", boat.health);
        dict.set("max_health", boat.max_health);
        dict.set("speed", boat.speed);

        if let Some((q, r)) = boat.destination {
            dict.set("destination_q", q);
            dict.set("destination_r", r);
        }

        if let Some(owner) = boat.owner_id {
            dict.set("owner_id", owner);
        }

        dict
    }
}
