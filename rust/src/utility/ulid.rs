use godot::prelude::*;
use std::time::{SystemTime, UNIX_EPOCH};
use rand::Rng;

/// ULID (Universally Unique Lexicographically Sortable Identifier)
/// 128-bit (16 bytes) identifier with timestamp and randomness
/// Format: 48-bit timestamp (6 bytes) + 80-bit random (10 bytes)
#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct UlidGenerator {
    base: Base<RefCounted>,
}

#[godot_api]
impl IRefCounted for UlidGenerator {
    fn init(base: Base<RefCounted>) -> Self {
        Self { base }
    }
}

#[godot_api]
impl UlidGenerator {
    /// Generate a new ULID as PackedByteArray (16 bytes)
    /// Returns: [timestamp_ms (6 bytes), random (10 bytes)]
    #[func]
    pub fn generate() -> PackedByteArray {
        let mut ulid = [0u8; 16];

        // Get current timestamp in milliseconds (48 bits / 6 bytes)
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("Time went backwards")
            .as_millis() as u64;

        // Truncate to 48 bits (6 bytes) to fit in ULID spec
        let timestamp_48bit = now & 0xFFFF_FFFF_FFFF;

        // Store timestamp in big-endian format (first 6 bytes)
        ulid[0] = ((timestamp_48bit >> 40) & 0xFF) as u8;
        ulid[1] = ((timestamp_48bit >> 32) & 0xFF) as u8;
        ulid[2] = ((timestamp_48bit >> 24) & 0xFF) as u8;
        ulid[3] = ((timestamp_48bit >> 16) & 0xFF) as u8;
        ulid[4] = ((timestamp_48bit >> 8) & 0xFF) as u8;
        ulid[5] = (timestamp_48bit & 0xFF) as u8;

        // Generate 10 random bytes (80 bits)
        let mut rng = rand::rng();
        rng.fill(&mut ulid[6..16]);

        // Convert to PackedByteArray
        PackedByteArray::from(&ulid[..])
    }

    /// Generate a new ULID and return as hex string (for debugging)
    #[func]
    pub fn generate_hex() -> GString {
        let ulid = Self::generate();
        let bytes: Vec<u8> = ulid.to_vec();
        let hex_string = bytes.iter()
            .map(|b| format!("{:02x}", b))
            .collect::<String>();
        GString::from(hex_string)
    }

    /// Convert ULID bytes to hex string
    #[func]
    pub fn to_hex(ulid: PackedByteArray) -> GString {
        let bytes: Vec<u8> = ulid.to_vec();
        let hex_string = bytes.iter()
            .map(|b| format!("{:02x}", b))
            .collect::<String>();
        GString::from(hex_string)
    }

    /// Extract timestamp from ULID (returns milliseconds since UNIX epoch)
    #[func]
    pub fn get_timestamp(ulid: PackedByteArray) -> u64 {
        if ulid.len() < 6 {
            return 0;
        }

        let bytes: Vec<u8> = ulid.to_vec();

        // Reconstruct 48-bit timestamp from first 6 bytes (big-endian)
        let timestamp = ((bytes[0] as u64) << 40)
            | ((bytes[1] as u64) << 32)
            | ((bytes[2] as u64) << 24)
            | ((bytes[3] as u64) << 16)
            | ((bytes[4] as u64) << 8)
            | (bytes[5] as u64);

        timestamp
    }

    /// Compare two ULIDs (returns -1 if a < b, 0 if equal, 1 if a > b)
    /// ULIDs are lexicographically sortable by timestamp
    #[func]
    pub fn compare(a: PackedByteArray, b: PackedByteArray) -> i32 {
        let a_bytes: Vec<u8> = a.to_vec();
        let b_bytes: Vec<u8> = b.to_vec();

        match a_bytes.cmp(&b_bytes) {
            std::cmp::Ordering::Less => -1,
            std::cmp::Ordering::Equal => 0,
            std::cmp::Ordering::Greater => 1,
        }
    }

    /// Check if two ULIDs are equal
    #[func]
    pub fn equals(a: PackedByteArray, b: PackedByteArray) -> bool {
        let a_bytes: Vec<u8> = a.to_vec();
        let b_bytes: Vec<u8> = b.to_vec();
        a_bytes == b_bytes
    }

    /// Create a zero/null ULID (all zeros)
    #[func]
    pub fn null_ulid() -> PackedByteArray {
        PackedByteArray::from(&[0u8; 16][..])
    }

    /// Check if ULID is null (all zeros)
    #[func]
    pub fn is_null(ulid: PackedByteArray) -> bool {
        let bytes: Vec<u8> = ulid.to_vec();
        bytes.iter().all(|&b| b == 0)
    }
}
