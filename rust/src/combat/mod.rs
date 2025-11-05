// Combat system module
// Combat logic now handled by UnifiedEventBridge Actor + combat worker
// This module only contains shared utilities (range calculations, etc.)

pub mod range_calculator;

pub use range_calculator::{hex_distance, is_in_range};
