// Combat state management structures

use std::sync::Arc;
use std::time::Instant;
use dashmap::DashMap;

/// Represents an active combat between two entities
#[derive(Debug, Clone)]
pub struct CombatInstance {
    pub attacker_ulid: Vec<u8>,
    pub defender_ulid: Vec<u8>,
    pub last_attack_time: Instant,
    pub attack_interval: f32,  // Seconds between attacks
    pub attacker_position: (i32, i32),  // Hex coordinates
    pub defender_position: (i32, i32),
}

impl CombatInstance {
    pub fn new(
        attacker_ulid: Vec<u8>,
        defender_ulid: Vec<u8>,
        attacker_position: (i32, i32),
        defender_position: (i32, i32),
        attack_interval: f32,
    ) -> Self {
        Self {
            attacker_ulid,
            defender_ulid,
            last_attack_time: Instant::now(),
            attack_interval,
            attacker_position,
            defender_position,
        }
    }

    /// Check if enough time has passed for next attack
    pub fn can_attack(&self) -> bool {
        self.last_attack_time.elapsed().as_secs_f32() >= self.attack_interval
    }

    /// Reset attack timer
    pub fn reset_attack_timer(&mut self) {
        self.last_attack_time = Instant::now();
    }
}

/// Events that can be queued for GDScript signals
#[derive(Debug, Clone)]
pub enum CombatEvent {
    CombatStarted {
        attacker_ulid: Vec<u8>,
        defender_ulid: Vec<u8>,
    },
    DamageDealt {
        attacker_ulid: Vec<u8>,
        defender_ulid: Vec<u8>,
        damage: f32,
        new_hp: f32,
    },
    CombatEnded {
        attacker_ulid: Vec<u8>,
        defender_ulid: Vec<u8>,
        winner_ulid: Vec<u8>,
    },
    EntityDied {
        ulid: Vec<u8>,
    },
}

/// Thread-safe storage for active combats
pub type CombatStateMap = Arc<DashMap<Vec<u8>, CombatInstance>>;

/// Thread-safe storage for registered combatants
#[derive(Debug, Clone)]
pub struct Combatant {
    pub ulid: Vec<u8>,
    pub player_ulid: Vec<u8>,  // Team affiliation
    pub position: (i32, i32),
    pub attack_interval: f32,
    pub is_alive: bool,
}

pub type CombatantMap = Arc<DashMap<Vec<u8>, Combatant>>;
