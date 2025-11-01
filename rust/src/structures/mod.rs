// Structures module - cities, villages, castles, markets, etc.
pub mod city;
pub mod manager;

// Re-export main types for easier imports
pub use city::{Structure, StructureFlags, StructureType};
pub use manager::StructureManager;
