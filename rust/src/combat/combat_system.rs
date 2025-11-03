// Combat system with worker thread for processing combat

use std::sync::Arc;
use std::thread;
use std::time::Duration;
use crossbeam_queue::SegQueue;
use parking_lot::RwLock;

use super::combat_state::{CombatEvent, CombatInstance, CombatStateMap, Combatant, CombatantMap};
use super::target_finder::find_closest_enemy;
use crate::npc::entity::{StatType, ENTITY_STATS};

/// Combat system singleton
pub struct CombatSystem {
    /// Map of active combats: attacker_ulid -> CombatInstance
    active_combats: CombatStateMap,

    /// Map of all registered combatants
    combatants: CombatantMap,

    /// Queue for combat events to send to GDScript
    event_queue: Arc<SegQueue<CombatEvent>>,

    /// Whether the system is running
    running: Arc<RwLock<bool>>,

    /// Combat tick rate in seconds
    tick_rate: f32,
}

impl CombatSystem {
    /// Create new combat system
    pub fn new(tick_rate: f32) -> Self {
        Self {
            active_combats: Arc::new(dashmap::DashMap::new()),
            combatants: Arc::new(dashmap::DashMap::new()),
            event_queue: Arc::new(SegQueue::new()),
            running: Arc::new(RwLock::new(false)),
            tick_rate,
        }
    }

    /// Start the combat worker thread
    pub fn start(&self) {
        let mut running = self.running.write();
        if *running {
            return; // Already running
        }
        *running = true;

        let active_combats = Arc::clone(&self.active_combats);
        let combatants = Arc::clone(&self.combatants);
        let event_queue = Arc::clone(&self.event_queue);
        let running_flag = Arc::clone(&self.running);
        let tick_rate = self.tick_rate;

        // Spawn worker thread
        thread::spawn(move || {
            let tick_duration = Duration::from_secs_f32(tick_rate);

            while *running_flag.read() {
                // Process all registered combatants
                Self::process_combat_tick(
                    &active_combats,
                    &combatants,
                    &event_queue,
                );

                thread::sleep(tick_duration);
            }
        });
    }

    /// Stop the combat worker thread
    pub fn stop(&self) {
        let mut running = self.running.write();
        *running = false;
    }

    /// Register a combatant (called when entity spawns)
    pub fn register_combatant(
        &self,
        ulid: Vec<u8>,
        player_ulid: Vec<u8>,
        position: (i32, i32),
        attack_interval: f32,
    ) {
        let combatant = Combatant {
            ulid: ulid.clone(),
            player_ulid,
            position,
            attack_interval,
            is_alive: true,
        };

        self.combatants.insert(ulid, combatant);
    }

    /// Unregister a combatant (called when entity dies/despawns)
    pub fn unregister_combatant(&self, ulid: &[u8]) {
        self.combatants.remove(ulid);

        // Remove from active combats
        self.active_combats.remove(ulid);

        // Remove any combat where this entity is the defender
        self.active_combats.retain(|_, combat| {
            combat.defender_ulid.as_slice() != ulid
        });
    }

    /// Update combatant position (called when entity moves)
    pub fn update_position(&self, ulid: &[u8], new_position: (i32, i32)) {
        if let Some(mut combatant) = self.combatants.get_mut(ulid) {
            combatant.position = new_position;
        }

        // Update position in active combat if attacker
        if let Some(mut combat) = self.active_combats.get_mut(ulid) {
            combat.attacker_position = new_position;
        }

        // Update position if defender in any combat
        for mut entry in self.active_combats.iter_mut() {
            if entry.defender_ulid.as_slice() == ulid {
                entry.defender_position = new_position;
            }
        }
    }

    /// Mark combatant as dead
    pub fn mark_dead(&self, ulid: &[u8]) {
        if let Some(mut combatant) = self.combatants.get_mut(ulid) {
            combatant.is_alive = false;
        }
    }

    /// Get next combat event from queue
    pub fn pop_event(&self) -> Option<CombatEvent> {
        self.event_queue.pop()
    }

    /// Main combat processing tick (runs in worker thread)
    fn process_combat_tick(
        active_combats: &CombatStateMap,
        combatants: &CombatantMap,
        event_queue: &Arc<SegQueue<CombatEvent>>,
    ) {
        // Process each registered combatant
        for entry in combatants.iter() {
            let attacker_ulid = entry.key().clone();
            let attacker = entry.value();

            // Skip dead entities
            if !attacker.is_alive {
                continue;
            }

            // Get attacker's range from stats
            let range = ENTITY_STATS
                .get(&attacker_ulid)
                .map(|stats| stats.get(StatType::Range))
                .unwrap_or(1.0) as i32;

            // Check if already in combat
            if let Some(mut combat) = active_combats.get_mut(&attacker_ulid) {
                // Combat exists - check if can attack
                if combat.can_attack() {
                    // Verify defender still valid and alive
                    let defender_alive = combatants
                        .get(&combat.defender_ulid)
                        .map(|d| d.is_alive)
                        .unwrap_or(false);

                    // Also check HP in case GDScript killed them via EntityManagerBridge
                    let defender_hp = ENTITY_STATS
                        .get(&combat.defender_ulid)
                        .map(|stats| stats.get(StatType::HP))
                        .unwrap_or(0.0);

                    if defender_alive && defender_hp > 0.0 {
                        // Execute attack
                        Self::execute_attack(
                            &attacker_ulid,
                            &combat.defender_ulid,
                            event_queue,
                        );
                        combat.reset_attack_timer();
                    } else {
                        // Defender died, end combat
                        let winner = attacker_ulid.clone();
                        let defender = combat.defender_ulid.clone();

                        drop(combat); // Release lock before removing
                        active_combats.remove(&attacker_ulid);

                        event_queue.push(CombatEvent::CombatEnded {
                            attacker_ulid: winner.clone(),
                            defender_ulid: defender,
                            winner_ulid: winner,
                        });
                    }
                }
            } else {
                // Not in combat - search for targets
                if let Some(target_ulid) = find_closest_enemy(&attacker_ulid, combatants, range) {
                    // Found enemy in range - start combat
                    let target_pos = combatants
                        .get(&target_ulid)
                        .map(|t| t.position)
                        .unwrap_or((0, 0));

                    let combat = CombatInstance::new(
                        attacker_ulid.clone(),
                        target_ulid.clone(),
                        attacker.position,
                        target_pos,
                        attacker.attack_interval,
                    );

                    active_combats.insert(attacker_ulid.clone(), combat);

                    // Queue combat started event
                    event_queue.push(CombatEvent::CombatStarted {
                        attacker_ulid: attacker_ulid.clone(),
                        defender_ulid: target_ulid,
                    });
                }
            }
        }
    }

    /// Execute an attack between two entities
    /// NOTE: This only calculates damage and queues events
    /// Actual damage application happens in GDScript via EntityManagerBridge (for signal emission)
    fn execute_attack(
        attacker_ulid: &[u8],
        defender_ulid: &[u8],
        event_queue: &Arc<SegQueue<CombatEvent>>,
    ) {
        // Get attacker's attack stat
        let attack = ENTITY_STATS
            .get(attacker_ulid)
            .map(|stats| stats.get(StatType::Attack))
            .unwrap_or(5.0);

        // Get defender's current HP for the event
        let current_hp = ENTITY_STATS
            .get(defender_ulid)
            .map(|stats| stats.get(StatType::HP))
            .unwrap_or(0.0);

        // Calculate what new HP would be (but don't apply yet)
        // GDScript will apply via EntityManagerBridge.take_damage() which triggers signals
        let new_hp = (current_hp - attack).max(0.0);

        // Queue damage event with calculated damage
        event_queue.push(CombatEvent::DamageDealt {
            attacker_ulid: attacker_ulid.to_vec(),
            defender_ulid: defender_ulid.to_vec(),
            damage: attack,  // Raw attack value (defense calculation in GDScript)
            new_hp: current_hp,  // Current HP (GDScript will update)
        });

        // Note: entity_died event will be triggered by EntityManagerBridge when HP reaches 0
    }
}

// Global combat system instance
use once_cell::sync::Lazy;

static COMBAT_SYSTEM: Lazy<CombatSystem> = Lazy::new(|| {
    CombatSystem::new(0.5) // 2 ticks per second (reduced CPU usage)
});

/// Get global combat system instance
pub fn get_combat_system() -> &'static CombatSystem {
    &COMBAT_SYSTEM
}

/// Initialize and start combat system
pub fn initialize() {
    get_combat_system().start();
}

/// Register a combatant
pub fn register_combatant(
    ulid: Vec<u8>,
    player_ulid: Vec<u8>,
    position: (i32, i32),
    attack_interval: f32,
) {
    get_combat_system().register_combatant(ulid, player_ulid, position, attack_interval);
}

/// Unregister a combatant
pub fn unregister_combatant(ulid: &[u8]) {
    get_combat_system().unregister_combatant(ulid);
}

/// Update combatant position
pub fn update_position(ulid: &[u8], position: (i32, i32)) {
    get_combat_system().update_position(ulid, position);
}

/// Mark combatant as dead
pub fn mark_dead(ulid: &[u8]) {
    get_combat_system().mark_dead(ulid);
}

/// Pop next combat event
pub fn pop_event() -> Option<CombatEvent> {
    get_combat_system().pop_event()
}
