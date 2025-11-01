use godot::prelude::*;
use bitflags::bitflags;

bitflags! {
    /// Bitwise flags for structure types - allows structures to have multiple properties
    /// Using i64 to match GDScript's 64-bit int type
    #[derive(Debug, Clone, Copy, PartialEq, Eq)]
    pub struct StructureFlags: i64 {
        const CITY         = 1 << 0;  // 1
        const VILLAGE      = 1 << 1;  // 2
        const CASTLE       = 1 << 2;  // 4
        const RUINS        = 1 << 3;  // 8
        const MARKET       = 1 << 4;  // 16
        const FORTIFIED    = 1 << 5;  // 32 - has defenses
        const TRADING_POST = 1 << 6;  // 64 - can trade
        const INHABITED    = 1 << 7;  // 128 - has population
        const HOSTILE      = 1 << 8;  // 256 - attacks on sight
        const ABANDONED    = 1 << 9;  // 512 - no longer active
    }
}

/// Helper class for GDScript to work with structure type flags
#[derive(GodotClass, Debug)]
#[class(init, base=RefCounted)]
pub struct StructureType {
    base: Base<RefCounted>,
}

#[godot_api]
impl StructureType {
    // Constants exposed to GDScript (i64 to match GDScript int)
    #[constant]
    const CITY: i64 = StructureFlags::CITY.bits();
    #[constant]
    const VILLAGE: i64 = StructureFlags::VILLAGE.bits();
    #[constant]
    const CASTLE: i64 = StructureFlags::CASTLE.bits();
    #[constant]
    const RUINS: i64 = StructureFlags::RUINS.bits();
    #[constant]
    const MARKET: i64 = StructureFlags::MARKET.bits();
    #[constant]
    const FORTIFIED: i64 = StructureFlags::FORTIFIED.bits();
    #[constant]
    const TRADING_POST: i64 = StructureFlags::TRADING_POST.bits();
    #[constant]
    const INHABITED: i64 = StructureFlags::INHABITED.bits();
    #[constant]
    const HOSTILE: i64 = StructureFlags::HOSTILE.bits();
    #[constant]
    const ABANDONED: i64 = StructureFlags::ABANDONED.bits();

    /// Check if flags contain a specific flag
    #[func]
    pub fn has_flag(flags: i64, flag: i64) -> bool {
        if let Some(flags_bits) = StructureFlags::from_bits(flags) {
            if let Some(flag_bits) = StructureFlags::from_bits(flag) {
                return flags_bits.contains(flag_bits);
            }
        }
        false
    }

    /// Add a flag to flags (bitwise OR)
    #[func]
    pub fn add_flag(flags: i64, flag: i64) -> i64 {
        let mut result = StructureFlags::from_bits_truncate(flags);
        result.insert(StructureFlags::from_bits_truncate(flag));
        result.bits()
    }

    /// Remove a flag from flags (bitwise AND NOT)
    #[func]
    pub fn remove_flag(flags: i64, flag: i64) -> i64 {
        let mut result = StructureFlags::from_bits_truncate(flags);
        result.remove(StructureFlags::from_bits_truncate(flag));
        result.bits()
    }

    /// Toggle a flag (bitwise XOR)
    #[func]
    pub fn toggle_flag(flags: i64, flag: i64) -> i64 {
        let mut result = StructureFlags::from_bits_truncate(flags);
        result ^= StructureFlags::from_bits_truncate(flag);
        result.bits()
    }

    /// Get the primary structure type name
    #[func]
    pub fn get_primary_type_name(flags: i64) -> GString {
        let flags_bits = StructureFlags::from_bits_truncate(flags);

        if flags_bits.contains(StructureFlags::CITY) {
            "City".into()
        } else if flags_bits.contains(StructureFlags::CASTLE) {
            "Castle".into()
        } else if flags_bits.contains(StructureFlags::VILLAGE) {
            "Village".into()
        } else if flags_bits.contains(StructureFlags::MARKET) {
            "Market".into()
        } else if flags_bits.contains(StructureFlags::RUINS) {
            "Ruins".into()
        } else {
            "Unknown".into()
        }
    }

    /// Get full description with modifiers (e.g., "Fortified City")
    #[func]
    pub fn get_full_description(flags: i64) -> GString {
        let flags_bits = StructureFlags::from_bits_truncate(flags);
        let mut parts = Vec::new();

        if flags_bits.contains(StructureFlags::ABANDONED) {
            parts.push("Abandoned");
        }
        if flags_bits.contains(StructureFlags::FORTIFIED) {
            parts.push("Fortified");
        }
        if flags_bits.contains(StructureFlags::HOSTILE) {
            parts.push("Hostile");
        }

        let base_type = Self::get_primary_type_name(flags);

        if parts.is_empty() {
            base_type
        } else {
            format!("{} {}", parts.join(" "), base_type).into()
        }
    }
}

/// Base structure data
#[derive(GodotClass, Debug)]
#[class(init, base=RefCounted)]
pub struct Structure {
    base: Base<RefCounted>,

    /// Unique identifier for this structure
    id: i64,

    /// Owner's ULID (player who owns this structure)
    /// Empty PackedByteArray means unowned/neutral
    owner_ulid: PackedByteArray,

    /// Type of structure (bitwise flags)
    structure_type: i64,

    /// Position in world coordinates
    position_x: f32,
    position_y: f32,

    /// Name of the structure
    name: GString,

    /// Population (for cities, villages)
    population: i64,

    /// Wealth level (affects market prices, guards, etc.)
    wealth: f32,

    /// Reputation/relationship with player (-100 to 100)
    reputation: f32,

    /// Whether the structure is active/intact
    is_active: bool,
}

#[godot_api]
impl Structure {
    /// Create a new structure with owner
    #[func]
    pub fn new_structure(
        id: i64,
        owner_ulid: PackedByteArray,
        structure_type: i64,
        x: f32,
        y: f32,
        name: GString,
    ) -> Gd<Self> {
        Gd::from_init_fn(|base| {
            Structure {
                base,
                id,
                owner_ulid,
                structure_type,
                position_x: x,
                position_y: y,
                name,
                population: 0,
                wealth: 50.0,
                reputation: 0.0,
                is_active: true,
            }
        })
    }

    /// Create an unowned/neutral structure
    #[func]
    pub fn new_neutral_structure(
        id: i64,
        structure_type: i64,
        x: f32,
        y: f32,
        name: GString,
    ) -> Gd<Self> {
        Self::new_structure(id, PackedByteArray::new(), structure_type, x, y, name)
    }

    // Getters
    #[func]
    pub fn get_id(&self) -> i64 {
        self.id
    }

    #[func]
    pub fn get_owner_ulid(&self) -> PackedByteArray {
        self.owner_ulid.clone()
    }

    #[func]
    pub fn get_structure_type(&self) -> i64 {
        self.structure_type
    }

    #[func]
    pub fn is_owned(&self) -> bool {
        !self.owner_ulid.is_empty()
    }

    #[func]
    pub fn is_owned_by(&self, player_ulid: PackedByteArray) -> bool {
        !self.owner_ulid.is_empty() && self.owner_ulid == player_ulid
    }

    #[func]
    pub fn get_position(&self) -> Vector2 {
        Vector2::new(self.position_x, self.position_y)
    }

    #[func]
    pub fn get_name(&self) -> GString {
        self.name.clone()
    }

    #[func]
    pub fn get_population(&self) -> i64 {
        self.population
    }

    #[func]
    pub fn get_wealth(&self) -> f32 {
        self.wealth
    }

    #[func]
    pub fn get_reputation(&self) -> f32 {
        self.reputation
    }

    #[func]
    pub fn is_structure_active(&self) -> bool {
        self.is_active
    }

    // Setters
    #[func]
    pub fn set_owner(&mut self, owner_ulid: PackedByteArray) {
        self.owner_ulid = owner_ulid;
    }

    #[func]
    pub fn remove_owner(&mut self) {
        self.owner_ulid = PackedByteArray::new();
    }

    #[func]
    pub fn set_name(&mut self, name: GString) {
        self.name = name;
    }

    #[func]
    pub fn set_population(&mut self, population: i64) {
        self.population = population.max(0);
    }

    #[func]
    pub fn set_wealth(&mut self, wealth: f32) {
        self.wealth = wealth.clamp(0.0, 100.0);
    }

    #[func]
    pub fn set_reputation(&mut self, reputation: f32) {
        self.reputation = reputation.clamp(-100.0, 100.0);
    }

    #[func]
    pub fn set_active(&mut self, active: bool) {
        self.is_active = active;
    }

    // Game logic methods
    #[func]
    pub fn modify_reputation(&mut self, delta: f32) {
        self.reputation = (self.reputation + delta).clamp(-100.0, 100.0);
    }

    #[func]
    pub fn modify_population(&mut self, delta: i64) {
        self.population = (self.population + delta).max(0);
    }

    #[func]
    pub fn modify_wealth(&mut self, delta: f32) {
        self.wealth = (self.wealth + delta).clamp(0.0, 100.0);
    }

    /// Get a description of the structure based on its type and state
    #[func]
    pub fn get_description(&self) -> GString {
        let flags = self.structure_type;

        if StructureType::has_flag(flags, StructureFlags::CITY.bits()) {
            if self.population > 1000 {
                "A bustling city with towering buildings and busy streets.".into()
            } else if self.population > 500 {
                "A growing city with expanding districts.".into()
            } else {
                "A small city with modest infrastructure.".into()
            }
        } else if StructureType::has_flag(flags, StructureFlags::VILLAGE.bits()) {
            if StructureType::has_flag(flags, StructureFlags::ABANDONED.bits()) || !self.is_active {
                "An abandoned village, eerily quiet.".into()
            } else {
                "A peaceful village with simple homes and farmland.".into()
            }
        } else if StructureType::has_flag(flags, StructureFlags::CASTLE.bits()) {
            if self.wealth > 70.0 {
                "An imposing fortress with well-maintained walls.".into()
            } else {
                "A weathered castle showing signs of age.".into()
            }
        } else if StructureType::has_flag(flags, StructureFlags::RUINS.bits()) {
            "Ancient ruins of a once-great structure.".into()
        } else if StructureType::has_flag(flags, StructureFlags::MARKET.bits()) {
            if self.wealth > 60.0 {
                "A thriving marketplace with exotic goods.".into()
            } else {
                "A modest market with basic supplies.".into()
            }
        } else {
            "An unknown structure.".into()
        }
    }

    #[func]
    pub fn has_type(&self, flag: i64) -> bool {
        StructureType::has_flag(self.structure_type, flag)
    }

    #[func]
    pub fn add_type(&mut self, flag: i64) {
        self.structure_type = StructureType::add_flag(self.structure_type, flag);
    }

    #[func]
    pub fn remove_type(&mut self, flag: i64) {
        self.structure_type = StructureType::remove_flag(self.structure_type, flag);
    }

    #[func]
    pub fn get_type_name(&self) -> GString {
        StructureType::get_full_description(self.structure_type)
    }

    /// Check if player can interact with this structure
    #[func]
    pub fn can_interact(&self) -> bool {
        self.is_active && self.reputation > -50.0
    }

    /// Get trade modifier based on reputation
    /// Returns a value from -0.5 to +0.5 (i.e., -50% to +50%)
    /// Good reputation (positive) = better prices (negative modifier = discount)
    /// Bad reputation (negative) = worse prices (positive modifier = markup)
    #[func]
    pub fn get_trade_modifier(&self) -> f32 {
        -self.reputation / 200.0
    }
}
