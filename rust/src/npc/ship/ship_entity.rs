use godot::prelude::*;

/// Ship state
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ShipState {
    Idle,
    Moving,
    Docked,
    Combat,
}

impl ShipState {
    pub fn to_string(&self) -> String {
        match self {
            ShipState::Idle => "idle".to_string(),
            ShipState::Moving => "moving".to_string(),
            ShipState::Docked => "docked".to_string(),
            ShipState::Combat => "combat".to_string(),
        }
    }

    pub fn from_string(s: &str) -> Self {
        match s {
            "idle" => ShipState::Idle,
            "moving" => ShipState::Moving,
            "docked" => ShipState::Docked,
            "combat" => ShipState::Combat,
            _ => ShipState::Idle,
        }
    }
}

/// Ship data structure (Rust source of truth)
#[derive(Debug, Clone)]
pub struct ShipData {
    pub ulid: Vec<u8>,              // 16-byte ULID
    pub position: (i32, i32),       // Current position (q, r) hex coords
    pub destination: Option<(i32, i32)>, // Target destination if moving
    pub state: ShipState,
    pub health: i32,
    pub max_health: i32,
    pub energy: i32,                // Energy points for movement
    pub max_energy: i32,
    pub speed: f32,
    pub owner_id: Option<i64>,      // Godot instance ID of owner (player, AI)
    pub cargo: Vec<u8>,             // Cargo data (can be expanded)
}

impl ShipData {
    /// Create a new ship
    pub fn new(ulid: Vec<u8>, position: (i32, i32)) -> Self {
        Self {
            ulid,
            position,
            destination: None,
            state: ShipState::Idle,
            health: 100,
            max_health: 100,
            energy: 100,
            max_energy: 100,
            speed: 1.0,
            owner_id: None,
            cargo: Vec::new(),
        }
    }

    /// Set destination and start moving
    pub fn set_destination(&mut self, dest: (i32, i32)) {
        self.destination = Some(dest);
        self.state = ShipState::Moving;
    }

    /// Update position (called when reaching destination)
    pub fn update_position(&mut self, new_pos: (i32, i32)) {
        self.position = new_pos;

        // Check if reached destination
        if let Some(dest) = self.destination {
            if dest == new_pos {
                self.destination = None;
                self.state = ShipState::Idle;
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
    pub fn create_ship_data(ulid: PackedByteArray, position_q: i32, position_r: i32) -> Dictionary {
        let ulid_vec: Vec<u8> = ulid.to_vec();
        let ship_data = ShipData::new(ulid_vec, (position_q, position_r));

        Self::ship_data_to_dict(&ship_data)
    }

    /// Convert ShipData to Dictionary
    fn ship_data_to_dict(ship: &ShipData) -> Dictionary {
        let mut dict = Dictionary::new();

        dict.set("ulid", PackedByteArray::from(&ship.ulid[..]));
        dict.set("position_q", ship.position.0);
        dict.set("position_r", ship.position.1);
        dict.set("state", ship.state.to_string());
        dict.set("health", ship.health);
        dict.set("max_health", ship.max_health);
        dict.set("energy", ship.energy);
        dict.set("max_energy", ship.max_energy);
        dict.set("speed", ship.speed);

        if let Some((q, r)) = ship.destination {
            dict.set("destination_q", q);
            dict.set("destination_r", r);
        }

        if let Some(owner) = ship.owner_id {
            dict.set("owner_id", owner);
        }

        dict
    }
}
