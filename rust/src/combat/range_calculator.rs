// Range and distance calculations for combat

/// Calculate hex distance using cube coordinates
/// Distance = max(|dx|, |dy|, |dz|) where z = -x - y
pub fn hex_distance(a: (i32, i32), b: (i32, i32)) -> i32 {
    let (ax, ay) = a;
    let (bx, by) = b;

    let dx = (ax - bx).abs();
    let dy = (ay - by).abs();

    // Convert axial to cube coordinates
    let az = -ax - ay;
    let bz = -bx - by;
    let dz = (az - bz).abs();

    dx.max(dy).max(dz)
}

/// Check if two positions are within attack range
pub fn is_in_range(attacker_pos: (i32, i32), target_pos: (i32, i32), range: i32) -> bool {
    hex_distance(attacker_pos, target_pos) <= range
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_hex_distance_same_tile() {
        assert_eq!(hex_distance((0, 0), (0, 0)), 0);
    }

    #[test]
    fn test_hex_distance_adjacent() {
        assert_eq!(hex_distance((0, 0), (1, 0)), 1);
        assert_eq!(hex_distance((0, 0), (0, 1)), 1);
        assert_eq!(hex_distance((0, 0), (-1, 1)), 1);
    }

    #[test]
    fn test_hex_distance_diagonal() {
        assert_eq!(hex_distance((0, 0), (2, 2)), 4);
    }

    #[test]
    fn test_is_in_range() {
        assert!(is_in_range((0, 0), (1, 0), 1));
        assert!(is_in_range((0, 0), (2, 0), 3));
        assert!(!is_in_range((0, 0), (5, 0), 3));
    }
}
