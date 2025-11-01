use godot::prelude::*;

/// NPC state
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NpcState {
    Idle,
    Moving,
    Interacting,
    Combat,
    Dead,
}

impl NpcState {
    pub fn to_string(&self) -> String {
        match self {
            NpcState::Idle => "idle".to_string(),
            NpcState::Moving => "moving".to_string(),
            NpcState::Interacting => "interacting".to_string(),
            NpcState::Combat => "combat".to_string(),
            NpcState::Dead => "dead".to_string(),
        }
    }

    pub fn from_string(s: &str) -> Self {
        match s {
            "idle" => NpcState::Idle,
            "moving" => NpcState::Moving,
            "interacting" => NpcState::Interacting,
            "combat" => NpcState::Combat,
            "dead" => NpcState::Dead,
            _ => NpcState::Idle,
        }
    }
}

/// NPC data structure (Rust source of truth)
#[derive(Debug, Clone)]
pub struct NpcData {
    pub ulid: Vec<u8>,              // 16-byte ULID
    pub position: (i32, i32),       // Current position (q, r) hex coords
    pub destination: Option<(i32, i32)>, // Target destination if moving
    pub state: NpcState,
    pub health: i32,
    pub max_health: i32,
    pub energy: i32,                // Energy points for movement
    pub max_energy: i32,
    pub speed: f32,
    pub owner_id: Option<i64>,      // Godot instance ID of owner (player, AI)
    pub npc_type: String,           // NPC type identifier (e.g., "villager", "guard", "merchant")
}

impl NpcData {
    /// Create a new NPC
    pub fn new(ulid: Vec<u8>, position: (i32, i32), npc_type: String) -> Self {
        Self {
            ulid,
            position,
            destination: None,
            state: NpcState::Idle,
            health: 100,
            max_health: 100,
            energy: 100,
            max_energy: 100,
            speed: 1.0,
            owner_id: None,
            npc_type,
        }
    }

    /// Set destination and start moving
    pub fn set_destination(&mut self, dest: (i32, i32)) {
        self.destination = Some(dest);
        self.state = NpcState::Moving;
    }

    /// Update position (called when reaching destination)
    pub fn update_position(&mut self, new_pos: (i32, i32)) {
        self.position = new_pos;

        // Check if reached destination
        if let Some(dest) = self.destination {
            if dest == new_pos {
                self.destination = None;
                self.state = NpcState::Idle;
            }
        }
    }

    /// Take damage
    pub fn take_damage(&mut self, damage: i32) {
        self.health = (self.health - damage).max(0);
        if self.health == 0 {
            self.state = NpcState::Dead;
        }
    }

    /// Heal
    pub fn heal(&mut self, amount: i32) {
        self.health = (self.health + amount).min(self.max_health);
    }

    /// Use energy
    pub fn use_energy(&mut self, amount: i32) -> bool {
        if self.energy >= amount {
            self.energy -= amount;
            true
        } else {
            false
        }
    }

    /// Restore energy
    pub fn restore_energy(&mut self, amount: i32) {
        self.energy = (self.energy + amount).min(self.max_energy);
    }

    /// Check if NPC is alive
    pub fn is_alive(&self) -> bool {
        self.health > 0 && self.state != NpcState::Dead
    }

    /// Check if NPC is idle
    pub fn is_idle(&self) -> bool {
        self.state == NpcState::Idle
    }

    /// Check if NPC is moving
    pub fn is_moving(&self) -> bool {
        self.state == NpcState::Moving
    }
}
