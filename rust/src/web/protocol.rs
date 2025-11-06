// Network protocol and message serialization for multiplayer communication

use serde::{Deserialize, Serialize};

/// Game network messages that can be sent between client and server
#[derive(Debug, Clone, Serialize, Deserialize, bincode::Encode, bincode::Decode)]
pub enum GameMessage {
    // === Client -> Server ===
    /// Initial handshake/authentication
    Connect {
        player_id: Vec<u8>,
        version: String,
        token: Option<String>,
    },

    /// Player movement command
    MoveEntity {
        ulid: Vec<u8>,
        target_position: (i32, i32),
    },

    /// Player attack command
    AttackEntity {
        attacker_ulid: Vec<u8>,
        target_ulid: Vec<u8>,
    },

    /// Spawn entity request
    SpawnEntity {
        entity_type: String,
        position: (i32, i32),
    },

    /// Card placement
    PlaceCard {
        x: i32,
        y: i32,
        ulid: Vec<u8>,
        suit: u8,
        value: u8,
    },

    /// Resource transaction
    SpendResources {
        cost: Vec<(i32, f32)>, // (resource_type, amount)
    },

    /// Chat message
    Chat {
        message: String,
    },

    // === Server -> Client ===
    /// Connection accepted
    Connected {
        player_ulid: Vec<u8>,
        session_id: String,
    },

    /// Connection rejected
    Rejected {
        reason: String,
    },

    /// Entity state update
    EntityUpdate {
        ulid: Vec<u8>,
        position: (i32, i32),
        hp: i32,
        state: i64,
    },

    /// Entity spawned in world
    EntitySpawned {
        ulid: Vec<u8>,
        entity_type: String,
        position: (i32, i32),
        owner_ulid: Option<Vec<u8>>,
    },

    /// Entity removed from world
    EntityRemoved {
        ulid: Vec<u8>,
    },

    /// Combat event
    CombatEvent {
        attacker_ulid: Vec<u8>,
        defender_ulid: Vec<u8>,
        damage: i32,
    },

    /// Resource state update
    ResourceUpdate {
        resource_type: i32,
        current: f32,
        cap: f32,
        rate: f32,
    },

    /// Card placed notification
    CardPlaced {
        x: i32,
        y: i32,
        ulid: Vec<u8>,
        suit: u8,
        value: u8,
    },

    /// Combo detected notification
    ComboDetected {
        hand_rank: i32,
        hand_name: String,
        card_positions: Vec<(i32, i32)>,
    },

    /// Chat message from another player
    ChatMessage {
        player_ulid: Vec<u8>,
        player_name: String,
        message: String,
    },

    // === Bidirectional ===
    /// Heartbeat/keepalive
    Ping,

    /// Heartbeat response
    Pong,

    /// Error message
    Error {
        code: u32,
        message: String,
    },
}

/// Network protocol handler for serialization/deserialization
pub struct NetworkProtocol;

impl NetworkProtocol {
    /// Serialize a game message to binary format using bincode
    pub fn serialize(message: &GameMessage) -> Result<Vec<u8>, String> {
        bincode::encode_to_vec(message, bincode::config::standard())
            .map_err(|e| format!("Serialization failed: {}", e))
    }

    /// Deserialize a game message from binary format using bincode
    pub fn deserialize(data: &[u8]) -> Result<GameMessage, String> {
        bincode::decode_from_slice(data, bincode::config::standard())
            .map(|(msg, _)| msg)
            .map_err(|e| format!("Deserialization failed: {}", e))
    }

    /// Serialize a game message to JSON string (for debugging or text-based protocols)
    pub fn serialize_json(message: &GameMessage) -> Result<String, String> {
        serde_json::to_string(message).map_err(|e| format!("JSON serialization failed: {}", e))
    }

    /// Deserialize a game message from JSON string
    pub fn deserialize_json(json: &str) -> Result<GameMessage, String> {
        serde_json::from_str(json).map_err(|e| format!("JSON deserialization failed: {}", e))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_serialize_deserialize_binary() {
        let msg = GameMessage::Connect {
            player_id: vec![1, 2, 3, 4],
            version: "0.1.0".to_string(),
            token: Some("test_token".to_string()),
        };

        let serialized = NetworkProtocol::serialize(&msg).expect("Serialization failed");
        let deserialized =
            NetworkProtocol::deserialize(&serialized).expect("Deserialization failed");

        match deserialized {
            GameMessage::Connect {
                player_id,
                version,
                token,
            } => {
                assert_eq!(player_id, vec![1, 2, 3, 4]);
                assert_eq!(version, "0.1.0");
                assert_eq!(token, Some("test_token".to_string()));
            }
            _ => panic!("Wrong message type"),
        }
    }

    #[test]
    fn test_serialize_deserialize_json() {
        let msg = GameMessage::Ping;

        let json = NetworkProtocol::serialize_json(&msg).expect("JSON serialization failed");
        let deserialized =
            NetworkProtocol::deserialize_json(&json).expect("JSON deserialization failed");

        match deserialized {
            GameMessage::Ping => {} // Success
            _ => panic!("Wrong message type"),
        }
    }

    #[test]
    fn test_entity_update() {
        let msg = GameMessage::EntityUpdate {
            ulid: vec![1, 2, 3, 4, 5, 6, 7, 8],
            position: (10, 20),
            hp: 100,
            state: 42,
        };

        let serialized = NetworkProtocol::serialize(&msg).expect("Serialization failed");
        let deserialized =
            NetworkProtocol::deserialize(&serialized).expect("Deserialization failed");

        match deserialized {
            GameMessage::EntityUpdate {
                ulid,
                position,
                hp,
                state,
            } => {
                assert_eq!(ulid, vec![1, 2, 3, 4, 5, 6, 7, 8]);
                assert_eq!(position, (10, 20));
                assert_eq!(hp, 100);
                assert_eq!(state, 42);
            }
            _ => panic!("Wrong message type"),
        }
    }
}
