use godot::prelude::*;
use super::card::CardData;
use std::collections::HashMap;

/// Resource type enum (matches GDScript ResourceLedger.R enum)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ResourceType {
    Gold = 0,    // Diamonds
    Food = 1,    // Hearts
    Labor = 2,   // Spades
    Faith = 3,   // Clubs
}

impl ResourceType {
    /// Get resource type from suit (0=Clubs, 1=Diamonds, 2=Hearts, 3=Spades)
    pub fn from_suit(suit: u8) -> Self {
        match suit {
            0 => ResourceType::Faith,   // Clubs -> Faith
            1 => ResourceType::Gold,    // Diamonds -> Gold
            2 => ResourceType::Food,    // Hearts -> Food
            3 => ResourceType::Labor,   // Spades -> Labor
            _ => ResourceType::Gold,    // Default to Gold
        }
    }

    pub fn to_string(&self) -> String {
        match self {
            ResourceType::Gold => "Gold".to_string(),
            ResourceType::Food => "Food".to_string(),
            ResourceType::Labor => "Labor".to_string(),
            ResourceType::Faith => "Faith".to_string(),
        }
    }
}

/// Resource bonus from a combo
#[derive(Debug, Clone)]
pub struct ResourceBonus {
    pub resource_type: ResourceType,
    pub resource_name: String,
    pub amount: f32,
}

/// Poker hand ranks (from weakest to strongest)
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum PokerHand {
    HighCard = 0,
    OnePair = 1,
    TwoPair = 2,
    ThreeOfAKind = 3,
    Straight = 4,
    Flush = 5,
    FullHouse = 6,
    FourOfAKind = 7,
    StraightFlush = 8,
    RoyalFlush = 9,
}

impl PokerHand {
    pub fn to_string(&self) -> String {
        match self {
            PokerHand::HighCard => "High Card".to_string(),
            PokerHand::OnePair => "One Pair".to_string(),
            PokerHand::TwoPair => "Two Pair".to_string(),
            PokerHand::ThreeOfAKind => "Three of a Kind".to_string(),
            PokerHand::Straight => "Straight".to_string(),
            PokerHand::Flush => "Flush".to_string(),
            PokerHand::FullHouse => "Full House".to_string(),
            PokerHand::FourOfAKind => "Four of a Kind".to_string(),
            PokerHand::StraightFlush => "Straight Flush".to_string(),
            PokerHand::RoyalFlush => "Royal Flush".to_string(),
        }
    }

    /// Get bonus multiplier for this hand
    pub fn bonus_multiplier(&self) -> f32 {
        match self {
            PokerHand::HighCard => 1.0,
            PokerHand::OnePair => 1.5,
            PokerHand::TwoPair => 2.0,
            PokerHand::ThreeOfAKind => 3.0,
            PokerHand::Straight => 4.0,
            PokerHand::Flush => 5.0,
            PokerHand::FullHouse => 7.0,
            PokerHand::FourOfAKind => 10.0,
            PokerHand::StraightFlush => 20.0,
            PokerHand::RoyalFlush => 50.0,
        }
    }
}

/// Card with position on hex grid
#[derive(Debug, Clone)]
pub struct PositionedCard {
    pub card: CardData,
    pub x: i32,
    pub y: i32,
    pub index: usize, // Original index in input array
}

/// Result of combo detection
#[derive(Debug, Clone)]
pub struct ComboResult {
    pub hand: PokerHand,
    pub hand_name: String,
    pub bonus_multiplier: f32,
    pub cards_used: Vec<usize>, // Indices of cards that form the combo
    pub positions: Vec<(i32, i32)>, // Hex positions of the combo
    pub resource_bonuses: Vec<ResourceBonus>, // Resource bonuses from this combo
}

impl ComboResult {
    pub fn new(hand: PokerHand) -> Self {
        Self {
            hand_name: hand.to_string(),
            bonus_multiplier: hand.bonus_multiplier(),
            hand,
            cards_used: Vec::new(),
            positions: Vec::new(),
            resource_bonuses: Vec::new(),
        }
    }

    pub fn with_cards(hand: PokerHand, cards: Vec<usize>, positions: Vec<(i32, i32)>) -> Self {
        Self {
            hand_name: hand.to_string(),
            bonus_multiplier: hand.bonus_multiplier(),
            hand,
            cards_used: cards,
            resource_bonuses: Vec::new(),
            positions,
        }
    }

    pub fn with_resources(hand: PokerHand, cards: Vec<usize>, positions: Vec<(i32, i32)>, line_cards: &[&CardData]) -> Self {
        let mut result = Self {
            hand_name: hand.to_string(),
            bonus_multiplier: hand.bonus_multiplier(),
            hand,
            cards_used: cards,
            positions,
            resource_bonuses: Vec::new(),
        };
        result.calculate_resource_bonuses(line_cards);
        result
    }

    fn calculate_resource_bonuses(&mut self, cards: &[&CardData]) {
        let mut suit_counts: HashMap<u8, usize> = HashMap::new();
        for card in cards.iter().filter(|c| !c.is_custom) {
            *suit_counts.entry(card.suit).or_insert(0) += 1;
        }
        let base_amount = 10.0;
        for (suit, count) in suit_counts.iter() {
            let resource_type = ResourceType::from_suit(*suit);
            let amount = base_amount * (*count as f32) * self.bonus_multiplier;
            self.resource_bonuses.push(ResourceBonus {
                resource_type,
                resource_name: resource_type.to_string(),
                amount,
            });
        }
    }
}

/// Hex grid directions (6 directions for flat-top hex)
const HEX_DIRECTIONS: [(i32, i32); 6] = [
    (1, 0),   // East
    (1, -1),  // Northeast
    (0, -1),  // Northwest
    (-1, 0),  // West
    (-1, 1),  // Southwest
    (0, 1),   // Southeast
];

/// Detect poker hands in hex grid lines
pub struct ComboDetector;

impl ComboDetector {
    /// Detect the best poker hand from positioned cards on hex grid
    /// Cards must be in a straight line, jokers (custom cards) can be skipped
    pub fn detect_combo(positioned_cards: &[PositionedCard]) -> ComboResult {
        if positioned_cards.is_empty() {
            return ComboResult::new(PokerHand::HighCard);
        }

        // Find all possible straight lines through the cards
        let lines = Self::find_all_lines(positioned_cards);

        // Check each line for the best hand
        let mut best_result = ComboResult::new(PokerHand::HighCard);

        for line in lines {
            if let Some(result) = Self::check_line_for_combos(&line, positioned_cards) {
                if result.hand > best_result.hand {
                    best_result = result;
                }
            }
        }

        best_result
    }

    /// Find all straight lines of 5+ cards (including jokers)
    fn find_all_lines(cards: &[PositionedCard]) -> Vec<Vec<usize>> {
        let mut lines = Vec::new();

        // Try starting from each card
        for (start_idx, start_card) in cards.iter().enumerate() {
            // Try each of the 6 hex directions
            for direction in &HEX_DIRECTIONS {
                if let Some(line) = Self::trace_line(start_idx, *direction, cards) {
                    if line.len() >= 5 {
                        // Check if this line already exists (might have found it from other direction)
                        if !Self::line_exists(&line, &lines) {
                            lines.push(line);
                        }
                    }
                }
            }
        }

        lines
    }

    /// Trace a line in a specific direction from a starting card
    fn trace_line(start_idx: usize, direction: (i32, i32), cards: &[PositionedCard]) -> Option<Vec<usize>> {
        let start = &cards[start_idx];
        let mut line = vec![start_idx];
        let mut current_pos = (start.x, start.y);

        // Trace forward
        loop {
            let next_pos = (current_pos.0 + direction.0, current_pos.1 + direction.1);

            if let Some(next_idx) = Self::find_card_at_position(&next_pos, cards) {
                line.push(next_idx);
                current_pos = next_pos;
            } else {
                break;
            }
        }

        // Trace backward
        current_pos = (start.x, start.y);
        let reverse_dir = (-direction.0, -direction.1);
        loop {
            let prev_pos = (current_pos.0 + reverse_dir.0, current_pos.1 + reverse_dir.1);

            if let Some(prev_idx) = Self::find_card_at_position(&prev_pos, cards) {
                line.insert(0, prev_idx);
                current_pos = prev_pos;
            } else {
                break;
            }
        }

        if line.len() >= 2 {
            Some(line)
        } else {
            None
        }
    }

    /// Find card index at specific position
    fn find_card_at_position(pos: &(i32, i32), cards: &[PositionedCard]) -> Option<usize> {
        cards.iter()
            .position(|c| c.x == pos.0 && c.y == pos.1)
    }

    /// Check if line already exists in the list
    fn line_exists(line: &[usize], lines: &[Vec<usize>]) -> bool {
        for existing in lines {
            if Self::same_line(line, existing) {
                return true;
            }
        }
        false
    }

    /// Check if two lines contain the same cards (regardless of order)
    fn same_line(a: &[usize], b: &[usize]) -> bool {
        if a.len() != b.len() {
            return false;
        }
        let mut a_sorted = a.to_vec();
        let mut b_sorted = b.to_vec();
        a_sorted.sort();
        b_sorted.sort();
        a_sorted == b_sorted
    }

    /// Check a line for poker combos (skipping jokers)
    fn check_line_for_combos(line: &[usize], all_cards: &[PositionedCard]) -> Option<ComboResult> {
        // Extract standard cards from line (skip jokers/custom cards)
        let line_cards: Vec<&CardData> = line.iter()
            .map(|&idx| &all_cards[idx].card)
            .filter(|c| !c.is_custom)
            .collect();

        // Need at least 2 cards for any combo (pairs)
        if line_cards.len() < 2 {
            return None;
        }

        // Check for hands (from strongest to weakest)
        // Note: Some hands require 5 cards, others can work with fewer
        if let Some(_) = Self::check_royal_flush(&line_cards) {
            let positions: Vec<(i32, i32)> = line.iter().map(|&idx| (all_cards[idx].x, all_cards[idx].y)).collect();
            return Some(ComboResult::with_resources(PokerHand::RoyalFlush, line.to_vec(), positions, &line_cards));
        }

        if let Some(_) = Self::check_straight_flush(&line_cards) {
            let positions: Vec<(i32, i32)> = line.iter().map(|&idx| (all_cards[idx].x, all_cards[idx].y)).collect();
            return Some(ComboResult::with_resources(PokerHand::StraightFlush, line.to_vec(), positions, &line_cards));
        }

        if let Some(_) = Self::check_four_of_a_kind(&line_cards) {
            let positions: Vec<(i32, i32)> = line.iter().map(|&idx| (all_cards[idx].x, all_cards[idx].y)).collect();
            return Some(ComboResult::with_resources(PokerHand::FourOfAKind, line.to_vec(), positions, &line_cards));
        }

        if let Some(_) = Self::check_full_house(&line_cards) {
            let positions: Vec<(i32, i32)> = line.iter().map(|&idx| (all_cards[idx].x, all_cards[idx].y)).collect();
            return Some(ComboResult::with_resources(PokerHand::FullHouse, line.to_vec(), positions, &line_cards));
        }

        if let Some(_) = Self::check_flush(&line_cards) {
            let positions: Vec<(i32, i32)> = line.iter().map(|&idx| (all_cards[idx].x, all_cards[idx].y)).collect();
            return Some(ComboResult::with_resources(PokerHand::Flush, line.to_vec(), positions, &line_cards));
        }

        if let Some(_) = Self::check_straight(&line_cards) {
            let positions: Vec<(i32, i32)> = line.iter().map(|&idx| (all_cards[idx].x, all_cards[idx].y)).collect();
            return Some(ComboResult::with_resources(PokerHand::Straight, line.to_vec(), positions, &line_cards));
        }

        if let Some(_) = Self::check_three_of_a_kind(&line_cards) {
            let positions: Vec<(i32, i32)> = line.iter().map(|&idx| (all_cards[idx].x, all_cards[idx].y)).collect();
            return Some(ComboResult::with_resources(PokerHand::ThreeOfAKind, line.to_vec(), positions, &line_cards));
        }

        if let Some(_) = Self::check_two_pair(&line_cards) {
            let positions: Vec<(i32, i32)> = line.iter().map(|&idx| (all_cards[idx].x, all_cards[idx].y)).collect();
            return Some(ComboResult::with_resources(PokerHand::TwoPair, line.to_vec(), positions, &line_cards));
        }

        if let Some(_) = Self::check_one_pair(&line_cards) {
            let positions: Vec<(i32, i32)> = line.iter().map(|&idx| (all_cards[idx].x, all_cards[idx].y)).collect();
            return Some(ComboResult::with_resources(PokerHand::OnePair, line.to_vec(), positions, &line_cards));
        }

        None
    }

    /// Count cards by value
    fn count_by_value(cards: &[&CardData]) -> HashMap<u8, usize> {
        let mut counts = HashMap::new();
        for card in cards {
            *counts.entry(card.value).or_insert(0) += 1;
        }
        counts
    }

    /// Count cards by suit
    fn count_by_suit(cards: &[&CardData]) -> HashMap<u8, usize> {
        let mut counts = HashMap::new();
        for card in cards {
            *counts.entry(card.suit).or_insert(0) += 1;
        }
        counts
    }

    // Poker hand checking functions (similar to before but simplified)

    fn check_royal_flush(cards: &[&CardData]) -> Option<()> {
        let by_suit = Self::count_by_suit(cards);
        for (_suit, count) in by_suit.iter() {
            if *count >= 5 {
                let values: Vec<u8> = cards.iter().map(|c| c.value).collect();
                if values.contains(&10) && values.contains(&11) && values.contains(&12)
                   && values.contains(&13) && values.contains(&1) {
                    return Some(());
                }
            }
        }
        None
    }

    fn check_straight_flush(cards: &[&CardData]) -> Option<()> {
        if Self::check_flush(cards).is_some() && Self::check_straight(cards).is_some() {
            return Some(());
        }
        None
    }

    fn check_four_of_a_kind(cards: &[&CardData]) -> Option<()> {
        let by_value = Self::count_by_value(cards);
        for (_value, count) in by_value.iter() {
            if *count == 4 {
                return Some(());
            }
        }
        None
    }

    fn check_full_house(cards: &[&CardData]) -> Option<()> {
        let by_value = Self::count_by_value(cards);
        let mut has_three = false;
        let mut has_pair = false;

        for (_value, count) in by_value.iter() {
            if *count == 3 {
                has_three = true;
            } else if *count == 2 {
                has_pair = true;
            }
        }

        if has_three && has_pair {
            Some(())
        } else {
            None
        }
    }

    fn check_flush(cards: &[&CardData]) -> Option<()> {
        let by_suit = Self::count_by_suit(cards);
        for (_suit, count) in by_suit.iter() {
            if *count >= 5 {
                return Some(());
            }
        }
        None
    }

    fn check_straight(cards: &[&CardData]) -> Option<()> {
        if cards.len() < 5 {
            return None;
        }

        let mut values: Vec<u8> = cards.iter().map(|c| c.value).collect();
        values.sort();
        values.dedup();

        if values.len() < 5 {
            return None;
        }

        // Check for consecutive values
        for window in values.windows(5) {
            let mut is_consecutive = true;
            for i in 0..4 {
                if window[i + 1] != window[i] + 1 {
                    is_consecutive = false;
                    break;
                }
            }
            if is_consecutive {
                return Some(());
            }
        }

        // Check for A-2-3-4-5 (Ace low straight)
        if values.contains(&1) && values.contains(&2) && values.contains(&3)
           && values.contains(&4) && values.contains(&5) {
            return Some(());
        }

        None
    }

    fn check_three_of_a_kind(cards: &[&CardData]) -> Option<()> {
        let by_value = Self::count_by_value(cards);
        for (_value, count) in by_value.iter() {
            if *count == 3 {
                return Some(());
            }
        }
        None
    }

    fn check_two_pair(cards: &[&CardData]) -> Option<()> {
        let by_value = Self::count_by_value(cards);
        let pairs = by_value.values().filter(|&&count| count == 2).count();
        if pairs >= 2 {
            Some(())
        } else {
            None
        }
    }

    fn check_one_pair(cards: &[&CardData]) -> Option<()> {
        let by_value = Self::count_by_value(cards);
        for (_value, count) in by_value.iter() {
            if *count == 2 {
                return Some(());
            }
        }
        None
    }
}

use std::sync::{Arc, Mutex};
use std::sync::mpsc::{channel, Sender, Receiver};
use std::thread;

/// Request for combo detection
struct ComboDetectionRequest {
    request_id: u64,
    cards: Vec<PositionedCard>,
}

/// Result from combo detection
struct ComboDetectionResult {
    request_id: u64,
    hand_name: String,
    bonus_multiplier: f32,
    hand_rank: u8,
    card_indices: Vec<usize>,
    positions: Vec<(i32, i32)>,
    resource_bonuses: Vec<ResourceBonus>,
}

/// Godot-exposed combo detector with worker threads
#[derive(GodotClass)]
#[class(base=Node)]
pub struct CardComboDetector {
    base: Base<Node>,

    // Worker thread communication
    request_tx: Arc<Mutex<Option<Sender<ComboDetectionRequest>>>>,
    result_rx: Arc<Mutex<Option<Receiver<ComboDetectionResult>>>>,
    worker_handle: Option<thread::JoinHandle<()>>,

    // Request ID counter
    next_request_id: Arc<Mutex<u64>>,
}

#[godot_api]
impl INode for CardComboDetector {
    fn init(base: Base<Node>) -> Self {
        Self {
            base,
            request_tx: Arc::new(Mutex::new(None)),
            result_rx: Arc::new(Mutex::new(None)),
            worker_handle: None,
            next_request_id: Arc::new(Mutex::new(0)),
        }
    }

    fn process(&mut self, _delta: f64) {
        // Check for results from worker thread
        self.poll_results();
    }
}

#[godot_api]
impl CardComboDetector {
    /// Signal emitted when combo detection completes
    /// Arguments: request_id (u64), result (Dictionary)
    #[signal]
    fn combo_found(request_id: u64, result: Dictionary);

    /// Start worker thread
    #[func]
    fn start_worker(&mut self) {
        let (request_tx, request_rx) = channel::<ComboDetectionRequest>();
        let (result_tx, result_rx) = channel::<ComboDetectionResult>();

        *self.request_tx.lock().unwrap() = Some(request_tx);
        *self.result_rx.lock().unwrap() = Some(result_rx);

        // Spawn worker thread
        let worker_handle = thread::spawn(move || {
            godot_print!("CardComboDetector: Worker thread started");

            loop {
                match request_rx.recv() {
                    Ok(request) => {
                        // Process combo detection
                        let combo_result = ComboDetector::detect_combo(&request.cards);

                        // Send result back
                        let result = ComboDetectionResult {
                            request_id: request.request_id,
                            hand_name: combo_result.hand_name,
                            bonus_multiplier: combo_result.bonus_multiplier,
                            hand_rank: combo_result.hand as u8,
                            card_indices: combo_result.cards_used,
                            positions: combo_result.positions,
                            resource_bonuses: combo_result.resource_bonuses,
                        };

                        if result_tx.send(result).is_err() {
                            godot_error!("CardComboDetector: Failed to send result");
                            break;
                        }
                    }
                    Err(_) => {
                        godot_print!("CardComboDetector: Worker thread shutting down");
                        break;
                    }
                }
            }
        });

        self.worker_handle = Some(worker_handle);
    }

    /// Stop worker thread
    #[func]
    fn stop_worker(&mut self) {
        // Drop the sender to signal thread to stop
        *self.request_tx.lock().unwrap() = None;

        if let Some(handle) = self.worker_handle.take() {
            let _ = handle.join();
        }
    }

    /// Request combo detection (async, result via signal)
    /// Accepts PackedByteArray with serialized card data for maximum performance
    /// Format per card (31 bytes): [16 ULID][1 suit][1 value][4 card_id][1 is_custom][4 x][4 y]
    /// Returns request_id for tracking
    #[func]
    fn request_combo_detection(&mut self, card_data: PackedByteArray) -> u64 {
        // Deserialize cards from packed buffer
        let positioned_cards = Self::deserialize_cards(&card_data);

        if positioned_cards.is_empty() {
            godot_error!("CardComboDetector: Failed to deserialize cards or empty data");
            return 0; // Invalid request
        }

        // Generate request ID
        let request_id = {
            let mut next_id = self.next_request_id.lock().unwrap();
            let id = *next_id;
            *next_id += 1;
            id
        };

        // Send request to worker thread
        if let Some(tx) = self.request_tx.lock().unwrap().as_ref() {
            let request = ComboDetectionRequest {
                request_id,
                cards: positioned_cards,
            };

            if tx.send(request).is_err() {
                godot_error!("CardComboDetector: Failed to send request to worker");
                return 0;
            }
        } else {
            godot_error!("CardComboDetector: Worker not started!");
            return 0;
        }

        request_id
    }

    /// Poll for results from worker thread (called in process())
    fn poll_results(&mut self) {
        // Collect results without holding the lock
        let results: Vec<ComboDetectionResult> = {
            if let Some(rx) = self.result_rx.lock().unwrap().as_ref() {
                let mut collected = Vec::new();
                while let Ok(result) = rx.try_recv() {
                    collected.push(result);
                }
                collected
            } else {
                Vec::new()
            }
        };

        // Process results and emit signals (lock is released)
        for result in results {
            // Convert to Godot Dictionary
            let mut dict = Dictionary::new();
            dict.set("hand_name", result.hand_name.as_str());
            dict.set("bonus_multiplier", result.bonus_multiplier);
            dict.set("hand_rank", result.hand_rank as i32);

            let mut indices_array = Array::<i32>::new();
            for idx in result.card_indices {
                indices_array.push(idx as i32);
            }
            dict.set("card_indices", indices_array);

            let mut positions_array = Array::<Dictionary>::new();
            for (x, y) in result.positions {
                let mut pos_dict = Dictionary::new();
                pos_dict.set("x", x);
                pos_dict.set("y", y);
                positions_array.push(&pos_dict);
            }
            dict.set("positions", positions_array);

            // Add resource bonuses
            let mut resources_array = Array::<Dictionary>::new();
            for bonus in result.resource_bonuses {
                let mut res_dict = Dictionary::new();
                res_dict.set("resource_type", bonus.resource_type as i32);
                res_dict.set("resource_name", bonus.resource_name.as_str());
                res_dict.set("amount", bonus.amount);
                resources_array.push(&res_dict);
            }
            dict.set("resource_bonuses", resources_array);

            // Emit signal with result
            self.base_mut().emit_signal("combo_found", &[result.request_id.to_variant(), dict.to_variant()]);
        }
    }

    /// Deserialize cards from PackedByteArray
    /// Format per card (31 bytes): [16 ULID][1 suit][1 value][4 card_id][1 is_custom][4 x][4 y]
    fn deserialize_cards(data: &PackedByteArray) -> Vec<PositionedCard> {
        const CARD_SIZE: usize = 31;
        let bytes = data.as_slice();

        if bytes.len() % CARD_SIZE != 0 {
            godot_error!("CardComboDetector: Invalid card data size. Expected multiple of {} bytes, got {}", CARD_SIZE, bytes.len());
            return Vec::new();
        }

        let card_count = bytes.len() / CARD_SIZE;
        let mut cards = Vec::with_capacity(card_count);

        for i in 0..card_count {
            let offset = i * CARD_SIZE;
            let card_bytes = &bytes[offset..offset + CARD_SIZE];

            // Parse card data
            let mut ulid = [0u8; 16];
            ulid.copy_from_slice(&card_bytes[0..16]);

            let suit = card_bytes[16];
            let value = card_bytes[17];

            let card_id = i32::from_le_bytes([
                card_bytes[18],
                card_bytes[19],
                card_bytes[20],
                card_bytes[21],
            ]);

            let is_custom = card_bytes[22] != 0;

            let x = i32::from_le_bytes([
                card_bytes[23],
                card_bytes[24],
                card_bytes[25],
                card_bytes[26],
            ]);

            let y = i32::from_le_bytes([
                card_bytes[27],
                card_bytes[28],
                card_bytes[29],
                card_bytes[30],
            ]);

            cards.push(PositionedCard {
                card: CardData {
                    ulid: ulid.to_vec(),
                    suit,
                    value,
                    card_id,
                    is_custom,
                    state: super::card::CardState::OnBoard,
                    position: Some((x, y)),
                    owner_id: None,
                },
                x,
                y,
                index: i,
            });
        }

        cards
    }

    /// Helper: Convert Godot Dictionary to PositionedCard (DEPRECATED - use PackedByteArray)
    fn dict_to_positioned_card(dict: &Dictionary, index: usize) -> Option<PositionedCard> {
        let ulid = dict.get("ulid")?.to::<PackedByteArray>();
        let suit = dict.get("suit")?.to::<u8>();
        let value = dict.get("value")?.to::<u8>();
        let card_id = dict.get("card_id")?.to::<i32>();
        let is_custom = dict.get("is_custom")?.to::<bool>();
        let x = dict.get("x")?.to::<i32>();
        let y = dict.get("y")?.to::<i32>();

        Some(PositionedCard {
            card: CardData {
                ulid: ulid.to_vec(),
                suit,
                value,
                card_id,
                is_custom,
                state: super::card::CardState::OnBoard,
                position: Some((x, y)),
                owner_id: None,
            },
            x,
            y,
            index,
        })
    }
}
