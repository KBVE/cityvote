use godot::prelude::*;

/// Card state enum
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CardState {
    InDeck,
    InHand,
    OnBoard,
    Discarded,
}

impl CardState {
    pub fn to_string(&self) -> String {
        match self {
            CardState::InDeck => "in_deck".to_string(),
            CardState::InHand => "in_hand".to_string(),
            CardState::OnBoard => "on_board".to_string(),
            CardState::Discarded => "discarded".to_string(),
        }
    }

    pub fn from_string(s: &str) -> Self {
        match s {
            "in_deck" => CardState::InDeck,
            "in_hand" => CardState::InHand,
            "on_board" => CardState::OnBoard,
            "discarded" => CardState::Discarded,
            _ => CardState::InDeck,
        }
    }
}

/// Card data structure (Rust source of truth)
/// This is NOT a Godot node - it's pure data
#[derive(Debug, Clone)]
pub struct CardData {
    pub ulid: Vec<u8>,           // 16-byte ULID
    pub suit: u8,                // 0-3 for standard suits, 4 for custom
    pub value: u8,               // 1-13 for standard, custom IDs for special cards
    pub card_id: i32,            // Atlas card ID (0-53)
    pub is_custom: bool,         // Is this a custom card?
    pub state: CardState,        // Current state
    pub position: Option<(i32, i32)>, // Board position if placed (x, y)
    pub owner_id: Option<i64>,   // Godot instance ID of owner (player, deck, etc)
}

impl CardData {
    /// Create a new standard card
    pub fn new_standard(ulid: Vec<u8>, suit: u8, value: u8) -> Self {
        assert!(suit <= 3, "Standard suit must be 0-3");
        assert!(value >= 1 && value <= 13, "Standard value must be 1-13");

        let card_id = (suit as i32) * 13 + (value as i32 - 1);

        Self {
            ulid,
            suit,
            value,
            card_id,
            is_custom: false,
            state: CardState::InDeck,
            position: None,
            owner_id: None,
        }
    }

    /// Create a new custom card
    pub fn new_custom(ulid: Vec<u8>, card_id: i32) -> Self {
        assert!(card_id >= 52, "Custom card_id must be >= 52");

        Self {
            ulid,
            suit: 4,  // Custom suit
            value: 0,
            card_id,
            is_custom: true,
            state: CardState::InDeck,
            position: None,
            owner_id: None,
        }
    }

    /// Update card state
    pub fn set_state(&mut self, state: CardState) {
        self.state = state;
    }

    /// Place card on board
    pub fn place_on_board(&mut self, x: i32, y: i32) {
        self.state = CardState::OnBoard;
        self.position = Some((x, y));
    }

    /// Remove card from board
    pub fn remove_from_board(&mut self) {
        self.position = None;
    }

    /// Get card name
    pub fn get_name(&self) -> String {
        if self.is_custom {
            match self.card_id {
                52 => "Vikings Special".to_string(),
                53 => "Dino Special".to_string(),
                _ => format!("Custom Card {}", self.card_id),
            }
        } else {
            let suit_names = ["Clubs", "Diamonds", "Hearts", "Spades"];
            let value_names = ["Ace", "2", "3", "4", "5", "6", "7", "8", "9", "10", "Jack", "Queen", "King"];
            format!("{} of {}", value_names[(self.value - 1) as usize], suit_names[self.suit as usize])
        }
    }
}

/// Godot-exposed card manager
/// Manages Card data structures and syncs with Godot nodes
#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct CardManager {
    base: Base<RefCounted>,
}

#[godot_api]
impl IRefCounted for CardManager {
    fn init(base: Base<RefCounted>) -> Self {
        Self { base }
    }
}

#[godot_api]
impl CardManager {
    /// Create card data and return as Dictionary for GDScript
    #[func]
    pub fn create_card_data(ulid: PackedByteArray, suit: i32, value: i32, is_custom: bool) -> Dictionary {
        let ulid_vec: Vec<u8> = ulid.to_vec();

        let card_data = if is_custom {
            let card_id = value; // For custom cards, value IS the card_id
            CardData::new_custom(ulid_vec, card_id)
        } else {
            CardData::new_standard(ulid_vec, suit as u8, value as u8)
        };

        Self::card_data_to_dict(&card_data)
    }

    /// Convert CardData to Godot Dictionary
    fn card_data_to_dict(card: &CardData) -> Dictionary {
        let mut dict = Dictionary::new();

        dict.set("ulid", PackedByteArray::from(&card.ulid[..]));
        dict.set("suit", card.suit);
        dict.set("value", card.value);
        dict.set("card_id", card.card_id);
        dict.set("is_custom", card.is_custom);
        dict.set("state", card.state.to_string());

        if let Some((x, y)) = card.position {
            dict.set("position_x", x);
            dict.set("position_y", y);
        }

        if let Some(owner) = card.owner_id {
            dict.set("owner_id", owner);
        }

        dict
    }

    /// Get card name from suit and value
    #[func]
    pub fn get_card_name(suit: i32, value: i32, is_custom: bool) -> GString {
        if is_custom {
            match value {
                52 => GString::from("Vikings Special"),
                53 => GString::from("Dino Special"),
                _ => GString::from(format!("Custom Card {}", value)),
            }
        } else {
            let suit_names = ["Clubs", "Diamonds", "Hearts", "Spades"];
            let value_names = ["Ace", "2", "3", "4", "5", "6", "7", "8", "9", "10", "Jack", "Queen", "King"];

            if suit >= 0 && suit < 4 && value >= 1 && value <= 13 {
                GString::from(format!("{} of {}",
                    value_names[(value - 1) as usize],
                    suit_names[suit as usize]
                ))
            } else {
                GString::from("Invalid Card")
            }
        }
    }
}
