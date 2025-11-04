use super::entity::{EntityData, ENTITY_DATA};
use super::spawn_manager::PENDING_SPAWNS;
use crossbeam_queue::SegQueue;
use std::sync::Arc;
use std::thread;

/// Commands for the entity worker thread
#[derive(Debug, Clone)]
pub enum EntityCommand {
    UpdatePosition {
        ulid: Vec<u8>,
        position: (i32, i32),
    },
    UpdateState {
        ulid: Vec<u8>,
        state: i64,
    },
    SetDestination {
        ulid: Vec<u8>,
        destination: Option<(i32, i32)>,
    },
    Insert {
        ulid: Vec<u8>,
        entity: EntityData,
    },
    Remove {
        ulid: Vec<u8>,
    },
}

/// Global command queue for entity updates
static ENTITY_COMMAND_QUEUE: once_cell::sync::Lazy<Arc<SegQueue<EntityCommand>>> =
    once_cell::sync::Lazy::new(|| Arc::new(SegQueue::new()));

/// Start the entity data worker thread
/// This thread processes all write operations to ENTITY_DATA
pub fn start_entity_worker() {
    let queue = Arc::clone(&ENTITY_COMMAND_QUEUE);

    thread::Builder::new()
        .name("entity-worker".to_string())
        .spawn(move || {
            godot::prelude::godot_print!("Entity worker thread started");

            loop {
                // Process all pending commands
                while let Some(cmd) = queue.pop() {
                    match cmd {
                        EntityCommand::UpdatePosition { ulid, position } => {
                            if let Some(mut entity) = ENTITY_DATA.get_mut(&ulid) {
                                entity.position = position;
                            }
                        }
                        EntityCommand::UpdateState { ulid, state } => {
                            if let Some(mut entity) = ENTITY_DATA.get_mut(&ulid) {
                                entity.state = state;
                            }
                        }
                        EntityCommand::SetDestination { ulid, destination } => {
                            if let Some(mut entity) = ENTITY_DATA.get_mut(&ulid) {
                                entity.destination = destination;
                            }
                        }
                        EntityCommand::Insert { ulid, entity } => {
                            // Remove from pending spawns (now safely inserted)
                            PENDING_SPAWNS.remove(&entity.position);
                            ENTITY_DATA.insert(ulid, entity);
                        }
                        EntityCommand::Remove { ulid } => {
                            ENTITY_DATA.remove(&ulid);
                        }
                    }
                }

                // Sleep briefly to avoid spinning
                thread::sleep(std::time::Duration::from_micros(100));
            }
        })
        .expect("Failed to start entity worker thread");
}

/// Queue a command to update entity position
#[inline]
pub fn queue_update_position(ulid: Vec<u8>, position: (i32, i32)) {
    ENTITY_COMMAND_QUEUE.push(EntityCommand::UpdatePosition { ulid, position });
}

/// Queue a command to update entity state
#[inline]
pub fn queue_update_state(ulid: Vec<u8>, state: i64) {
    ENTITY_COMMAND_QUEUE.push(EntityCommand::UpdateState { ulid, state });
}

/// Queue a command to set entity destination
#[inline]
pub fn queue_set_destination(ulid: Vec<u8>, destination: Option<(i32, i32)>) {
    ENTITY_COMMAND_QUEUE.push(EntityCommand::SetDestination { ulid, destination });
}

/// Queue a command to insert new entity
#[inline]
pub fn queue_insert_entity(ulid: Vec<u8>, entity: EntityData) {
    ENTITY_COMMAND_QUEUE.push(EntityCommand::Insert { ulid, entity });
}

/// Queue a command to remove entity
#[inline]
pub fn queue_remove_entity(ulid: Vec<u8>) {
    ENTITY_COMMAND_QUEUE.push(EntityCommand::Remove { ulid });
}

/// Get entity position (direct read from DashMap - lock-free)
#[inline]
pub fn get_entity_position(ulid: &[u8]) -> Option<(i32, i32)> {
    ENTITY_DATA.get(ulid).map(|entity| entity.position)
}

/// Get entity state (direct read from DashMap - lock-free)
#[inline]
pub fn get_entity_state(ulid: &[u8]) -> Option<i64> {
    ENTITY_DATA.get(ulid).map(|entity| entity.state)
}

/// Check if entity exists (direct read from DashMap - lock-free)
#[inline]
pub fn entity_exists(ulid: &[u8]) -> bool {
    ENTITY_DATA.contains_key(ulid)
}
