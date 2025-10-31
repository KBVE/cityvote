// Godot-Rust bridge for combat system

use godot::prelude::*;
use godot::classes::{Node, INode};
use super::combat_system;
use super::combat_state::CombatEvent;

/// Godot-Rust bridge for combat system
/// Manages combat processing and emits signals to GDScript
#[derive(GodotClass)]
#[class(base=Node)]
pub struct CombatBridge {
    #[base]
    base: Base<Node>,
}

#[godot_api]
impl INode for CombatBridge {
    fn init(base: Base<Node>) -> Self {
        // Initialize combat system
        combat_system::initialize();
        godot_print!("CombatBridge: Initialized combat system");

        Self { base }
    }

    fn ready(&mut self) {
        godot_print!("CombatBridge: Ready");
    }

    fn process(&mut self, _delta: f64) {
        // Poll for combat events and emit signals
        while let Some(event) = combat_system::pop_event() {
            self.emit_combat_event(event);
        }
    }
}

#[godot_api]
impl CombatBridge {
    /// Signal emitted when combat starts between two entities
    /// Args: attacker_ulid (PackedByteArray), defender_ulid (PackedByteArray)
    #[signal]
    fn combat_started(attacker_ulid: PackedByteArray, defender_ulid: PackedByteArray);

    /// Signal emitted when damage is dealt
    /// Args: attacker_ulid (PackedByteArray), defender_ulid (PackedByteArray), damage (float), new_hp (float)
    #[signal]
    fn damage_dealt(
        attacker_ulid: PackedByteArray,
        defender_ulid: PackedByteArray,
        damage: f32,
        new_hp: f32,
    );

    /// Signal emitted when combat ends
    /// Args: attacker_ulid (PackedByteArray), defender_ulid (PackedByteArray), winner_ulid (PackedByteArray)
    #[signal]
    fn combat_ended(
        attacker_ulid: PackedByteArray,
        defender_ulid: PackedByteArray,
        winner_ulid: PackedByteArray,
    );

    /// Signal emitted when an entity dies
    /// Args: ulid (PackedByteArray)
    #[signal]
    fn entity_died(ulid: PackedByteArray);

    /// Register a combatant for combat processing
    /// ulid: Entity's unique identifier
    /// player_ulid: Player/team identifier (empty for neutral)
    /// position: Hex grid position (x, y)
    /// attack_interval: Seconds between attacks (default 1.5)
    #[func]
    fn register_combatant(
        &mut self,
        ulid: PackedByteArray,
        player_ulid: PackedByteArray,
        position: Vector2i,
        attack_interval: f32,
    ) {
        let ulid_bytes: Vec<u8> = ulid.to_vec();
        let player_ulid_bytes: Vec<u8> = player_ulid.to_vec();
        let pos = (position.x, position.y);

        combat_system::register_combatant(ulid_bytes, player_ulid_bytes, pos, attack_interval);
    }

    /// Unregister a combatant (call when entity dies or despawns)
    #[func]
    fn unregister_combatant(&mut self, ulid: PackedByteArray) {
        let ulid_bytes: Vec<u8> = ulid.to_vec();
        combat_system::unregister_combatant(&ulid_bytes);
    }

    /// Update combatant position (call when entity moves)
    #[func]
    fn update_position(&mut self, ulid: PackedByteArray, position: Vector2i) {
        let ulid_bytes: Vec<u8> = ulid.to_vec();
        let pos = (position.x, position.y);

        combat_system::update_position(&ulid_bytes, pos);
    }

    /// Mark combatant as dead (stops them from attacking)
    #[func]
    fn mark_dead(&mut self, ulid: PackedByteArray) {
        let ulid_bytes: Vec<u8> = ulid.to_vec();
        combat_system::mark_dead(&ulid_bytes);
    }

    /// Internal: Emit signal for combat event
    fn emit_combat_event(&mut self, event: CombatEvent) {
        match event {
            CombatEvent::CombatStarted {
                attacker_ulid,
                defender_ulid,
            } => {
                let attacker_pba = PackedByteArray::from(&attacker_ulid[..]);
                let defender_pba = PackedByteArray::from(&defender_ulid[..]);

                self.base_mut().emit_signal(
                    "combat_started",
                    &[attacker_pba.to_variant(), defender_pba.to_variant()],
                );
            }
            CombatEvent::DamageDealt {
                attacker_ulid,
                defender_ulid,
                damage,
                new_hp,
            } => {
                let attacker_pba = PackedByteArray::from(&attacker_ulid[..]);
                let defender_pba = PackedByteArray::from(&defender_ulid[..]);

                self.base_mut().emit_signal(
                    "damage_dealt",
                    &[
                        attacker_pba.to_variant(),
                        defender_pba.to_variant(),
                        damage.to_variant(),
                        new_hp.to_variant(),
                    ],
                );
            }
            CombatEvent::CombatEnded {
                attacker_ulid,
                defender_ulid,
                winner_ulid,
            } => {
                let attacker_pba = PackedByteArray::from(&attacker_ulid[..]);
                let defender_pba = PackedByteArray::from(&defender_ulid[..]);
                let winner_pba = PackedByteArray::from(&winner_ulid[..]);

                self.base_mut().emit_signal(
                    "combat_ended",
                    &[
                        attacker_pba.to_variant(),
                        defender_pba.to_variant(),
                        winner_pba.to_variant(),
                    ],
                );
            }
            CombatEvent::EntityDied { ulid } => {
                let ulid_pba = PackedByteArray::from(&ulid[..]);

                self.base_mut().emit_signal(
                    "entity_died",
                    &[ulid_pba.to_variant()],
                );
            }
        }
    }
}
