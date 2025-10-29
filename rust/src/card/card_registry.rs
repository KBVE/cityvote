use godot::prelude::*;
use dashmap::DashMap;
use std::sync::Arc;
use super::card::{CardData, CardState};

/// Registry for tracking cards on the board
/// Maps hex coordinates to card data
#[derive(Clone)]
pub struct CardRegistry {
    /// Maps (x, y) hex coords -> CardData
    cards_by_position: Arc<DashMap<(i32, i32), CardData>>,
    /// Maps ULID -> (x, y) hex coords for reverse lookup
    position_by_ulid: Arc<DashMap<Vec<u8>, (i32, i32)>>,
}

impl CardRegistry {
    pub fn new() -> Self {
        Self {
            cards_by_position: Arc::new(DashMap::new()),
            position_by_ulid: Arc::new(DashMap::new()),
        }
    }

    /// Place a card on the board at specific hex coordinates
    pub fn place_card(&self, x: i32, y: i32, mut card: CardData) -> bool {
        // Check if position is already occupied
        if self.cards_by_position.contains_key(&(x, y)) {
            godot_warn!("CardRegistry: Position ({}, {}) is already occupied", x, y);
            return false;
        }

        // Check if card is already placed elsewhere
        if self.position_by_ulid.contains_key(&card.ulid) {
            godot_warn!("CardRegistry: Card already placed on board");
            return false;
        }

        // Update card state
        card.place_on_board(x, y);

        // Store the card
        let ulid = card.ulid.clone();
        self.cards_by_position.insert((x, y), card);
        self.position_by_ulid.insert(ulid, (x, y));

        true
    }

    /// Remove a card from the board by position
    pub fn remove_card_at(&self, x: i32, y: i32) -> Option<CardData> {
        if let Some((_, card)) = self.cards_by_position.remove(&(x, y)) {
            self.position_by_ulid.remove(&card.ulid);
            Some(card)
        } else {
            None
        }
    }

    /// Remove a card from the board by ULID
    pub fn remove_card_by_ulid(&self, ulid: &[u8]) -> Option<CardData> {
        if let Some((_, pos)) = self.position_by_ulid.remove(ulid) {
            if let Some((_, card)) = self.cards_by_position.remove(&pos) {
                return Some(card);
            }
        }
        None
    }

    /// Move a card from one position to another
    pub fn move_card(&self, from_x: i32, from_y: i32, to_x: i32, to_y: i32) -> bool {
        // Check if destination is occupied
        if self.cards_by_position.contains_key(&(to_x, to_y)) {
            return false;
        }

        // Remove from old position
        if let Some(mut card) = self.remove_card_at(from_x, from_y) {
            // Place at new position
            card.place_on_board(to_x, to_y);
            let ulid = card.ulid.clone();
            self.cards_by_position.insert((to_x, to_y), card);
            self.position_by_ulid.insert(ulid, (to_x, to_y));
            true
        } else {
            false
        }
    }

    /// Get card at specific position
    pub fn get_card_at(&self, x: i32, y: i32) -> Option<CardData> {
        self.cards_by_position.get(&(x, y)).map(|entry| entry.value().clone())
    }

    /// Get card by ULID
    pub fn get_card_by_ulid(&self, ulid: &[u8]) -> Option<CardData> {
        if let Some(pos_entry) = self.position_by_ulid.get(ulid) {
            let pos = *pos_entry.value();
            self.cards_by_position.get(&pos).map(|entry| entry.value().clone())
        } else {
            None
        }
    }

    /// Get position of a card by ULID
    pub fn get_position(&self, ulid: &[u8]) -> Option<(i32, i32)> {
        self.position_by_ulid.get(ulid).map(|entry| *entry.value())
    }

    /// Check if position has a card
    pub fn has_card_at(&self, x: i32, y: i32) -> bool {
        self.cards_by_position.contains_key(&(x, y))
    }

    /// Get all cards within a radius of a position
    pub fn get_cards_in_radius(&self, center_x: i32, center_y: i32, radius: i32) -> Vec<(i32, i32, CardData)> {
        let mut result = Vec::new();
        let radius_sq = radius * radius;

        for entry in self.cards_by_position.iter() {
            let (x, y) = *entry.key();
            let dx = x - center_x;
            let dy = y - center_y;
            let dist_sq = dx * dx + dy * dy;

            if dist_sq <= radius_sq {
                result.push((x, y, entry.value().clone()));
            }
        }

        result
    }

    /// Get all cards in a rectangular area
    pub fn get_cards_in_area(&self, min_x: i32, min_y: i32, max_x: i32, max_y: i32) -> Vec<(i32, i32, CardData)> {
        let mut result = Vec::new();

        for entry in self.cards_by_position.iter() {
            let (x, y) = *entry.key();
            if x >= min_x && x <= max_x && y >= min_y && y <= max_y {
                result.push((x, y, entry.value().clone()));
            }
        }

        result
    }

    /// Get all cards on the board
    pub fn get_all_cards(&self) -> Vec<(i32, i32, CardData)> {
        self.cards_by_position
            .iter()
            .map(|entry| {
                let (x, y) = *entry.key();
                (x, y, entry.value().clone())
            })
            .collect()
    }

    /// Get count of cards on board
    pub fn count(&self) -> usize {
        self.cards_by_position.len()
    }

    /// Clear all cards from the board
    pub fn clear(&self) {
        self.cards_by_position.clear();
        self.position_by_ulid.clear();
    }

    /// Update card state
    pub fn update_card_state(&self, ulid: &[u8], state: CardState) -> bool {
        if let Some(pos_entry) = self.position_by_ulid.get(ulid) {
            let pos = *pos_entry.value();
            if let Some(mut card_entry) = self.cards_by_position.get_mut(&pos) {
                card_entry.value_mut().set_state(state);
                return true;
            }
        }
        false
    }
}

/// Godot-exposed bridge for CardRegistry
#[derive(GodotClass)]
#[class(base=Node)]
pub struct CardRegistryBridge {
    base: Base<Node>,
    registry: CardRegistry,
}

#[godot_api]
impl INode for CardRegistryBridge {
    fn init(base: Base<Node>) -> Self {
        godot_print!("CardRegistryBridge initialized");
        Self {
            base,
            registry: CardRegistry::new(),
        }
    }
}

#[godot_api]
impl CardRegistryBridge {
    /// Place a card on the board
    /// Returns true if successful, false if position is occupied
    #[func]
    pub fn place_card(&self, x: i32, y: i32, ulid: PackedByteArray, suit: i32, value: i32, is_custom: bool, card_id: i32) -> bool {
        let ulid_vec: Vec<u8> = ulid.to_vec();

        if ulid_vec.len() != 16 {
            godot_error!("Invalid ULID: must be 16 bytes");
            return false;
        }

        let card_data = if is_custom {
            CardData::new_custom(ulid_vec, card_id)
        } else {
            CardData::new_standard(ulid_vec, suit as u8, value as u8)
        };

        self.registry.place_card(x, y, card_data)
    }

    /// Remove a card from the board by position
    /// Returns Dictionary with card data if found, empty Dictionary otherwise
    #[func]
    pub fn remove_card_at(&self, x: i32, y: i32) -> Dictionary {
        if let Some(card) = self.registry.remove_card_at(x, y) {
            Self::card_to_dict(&card)
        } else {
            Dictionary::new()
        }
    }

    /// Remove a card from the board by ULID
    #[func]
    pub fn remove_card_by_ulid(&self, ulid: PackedByteArray) -> Dictionary {
        let ulid_vec: Vec<u8> = ulid.to_vec();
        if let Some(card) = self.registry.remove_card_by_ulid(&ulid_vec) {
            Self::card_to_dict(&card)
        } else {
            Dictionary::new()
        }
    }

    /// Move a card from one position to another
    #[func]
    pub fn move_card(&self, from_x: i32, from_y: i32, to_x: i32, to_y: i32) -> bool {
        self.registry.move_card(from_x, from_y, to_x, to_y)
    }

    /// Get card at specific position
    #[func]
    pub fn get_card_at(&self, x: i32, y: i32) -> Dictionary {
        if let Some(card) = self.registry.get_card_at(x, y) {
            Self::card_to_dict(&card)
        } else {
            Dictionary::new()
        }
    }

    /// Get card by ULID
    #[func]
    pub fn get_card_by_ulid(&self, ulid: PackedByteArray) -> Dictionary {
        let ulid_vec: Vec<u8> = ulid.to_vec();
        if let Some(card) = self.registry.get_card_by_ulid(&ulid_vec) {
            Self::card_to_dict(&card)
        } else {
            Dictionary::new()
        }
    }

    /// Get position of a card by ULID
    /// Returns Vector2i with position, or (-1, -1) if not found
    #[func]
    pub fn get_position(&self, ulid: PackedByteArray) -> Vector2i {
        let ulid_vec: Vec<u8> = ulid.to_vec();
        if let Some((x, y)) = self.registry.get_position(&ulid_vec) {
            Vector2i::new(x, y)
        } else {
            Vector2i::new(-1, -1)
        }
    }

    /// Check if position has a card
    #[func]
    pub fn has_card_at(&self, x: i32, y: i32) -> bool {
        self.registry.has_card_at(x, y)
    }

    /// Get all cards within a radius
    /// Returns Array of Dictionaries with keys: x, y, card_data
    #[func]
    pub fn get_cards_in_radius(&self, center_x: i32, center_y: i32, radius: i32) -> Array<Dictionary> {
        let cards = self.registry.get_cards_in_radius(center_x, center_y, radius);
        let mut result = Array::new();

        for (x, y, card) in cards {
            let mut dict = Dictionary::new();
            dict.set("x", x);
            dict.set("y", y);
            dict.set("card", Self::card_to_dict(&card));
            result.push(&dict);
        }

        result
    }

    /// Get all cards in a rectangular area
    #[func]
    pub fn get_cards_in_area(&self, min_x: i32, min_y: i32, max_x: i32, max_y: i32) -> Array<Dictionary> {
        let cards = self.registry.get_cards_in_area(min_x, min_y, max_x, max_y);
        let mut result = Array::new();

        for (x, y, card) in cards {
            let mut dict = Dictionary::new();
            dict.set("x", x);
            dict.set("y", y);
            dict.set("card", Self::card_to_dict(&card));
            result.push(&dict);
        }

        result
    }

    /// Get all cards on the board
    #[func]
    pub fn get_all_cards(&self) -> Array<Dictionary> {
        let cards = self.registry.get_all_cards();
        let mut result = Array::new();

        for (x, y, card) in cards {
            let mut dict = Dictionary::new();
            dict.set("x", x);
            dict.set("y", y);
            dict.set("card", Self::card_to_dict(&card));
            result.push(&dict);
        }

        result
    }

    /// Get count of cards on board
    #[func]
    pub fn count(&self) -> i32 {
        self.registry.count() as i32
    }

    /// Clear all cards from the board
    #[func]
    pub fn clear(&self) {
        self.registry.clear();
    }

    /// Update card state
    #[func]
    pub fn update_card_state(&self, ulid: PackedByteArray, state: GString) -> bool {
        let ulid_vec: Vec<u8> = ulid.to_vec();
        let card_state = CardState::from_string(&state.to_string());
        self.registry.update_card_state(&ulid_vec, card_state)
    }

    /// Debug: Print all cards on board
    #[func]
    pub fn print_cards(&self) {
        godot_print!("=== Cards on Board ===");
        let cards = self.registry.get_all_cards();
        godot_print!("Total cards: {}", cards.len());

        for (x, y, card) in cards {
            godot_print!("  [{}, {}] - {} (state: {})", x, y, card.get_name(), card.state.to_string());
        }
    }

    /// Convert CardData to Dictionary for GDScript
    fn card_to_dict(card: &CardData) -> Dictionary {
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

        dict.set("name", card.get_name());

        dict
    }
}
