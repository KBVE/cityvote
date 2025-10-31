// Target acquisition and enemy detection

use super::combat_state::{Combatant, CombatantMap};
use super::range_calculator::{hex_distance, is_in_range};

/// Find the closest enemy within attack range
/// Returns None if no valid targets found
pub fn find_closest_enemy(
    attacker_ulid: &[u8],
    combatants: &CombatantMap,
    range: i32,
) -> Option<Vec<u8>> {
    // Get attacker info
    let attacker = combatants.get(attacker_ulid)?;
    let attacker_pos = attacker.position;
    let attacker_team = attacker.player_ulid.clone();

    let mut closest_enemy: Option<(Vec<u8>, i32)> = None;

    // Iterate through all combatants to find enemies
    for entry in combatants.iter() {
        let defender_ulid = entry.key();
        let defender = entry.value();

        // Skip self
        if defender_ulid == attacker_ulid {
            continue;
        }

        // Skip dead entities
        if !defender.is_alive {
            continue;
        }

        // Skip same team (compare player_ulid)
        if defender.player_ulid == attacker_team {
            continue;
        }

        // Check if in range
        if !is_in_range(attacker_pos, defender.position, range) {
            continue;
        }

        // Calculate distance
        let distance = hex_distance(attacker_pos, defender.position);

        // Update closest if this is closer
        match &closest_enemy {
            None => closest_enemy = Some((defender_ulid.clone(), distance)),
            Some((_, prev_distance)) => {
                if distance < *prev_distance {
                    closest_enemy = Some((defender_ulid.clone(), distance));
                }
            }
        }
    }

    closest_enemy.map(|(ulid, _)| ulid)
}

/// Find all enemies within range (for future AoE attacks)
pub fn find_all_enemies_in_range(
    attacker_ulid: &[u8],
    combatants: &CombatantMap,
    range: i32,
) -> Vec<Vec<u8>> {
    let attacker = match combatants.get(attacker_ulid) {
        Some(a) => a,
        None => return vec![],
    };

    let attacker_pos = attacker.position;
    let attacker_team = attacker.player_ulid.clone();

    let mut enemies = Vec::new();

    for entry in combatants.iter() {
        let defender_ulid = entry.key();
        let defender = entry.value();

        // Skip self, dead, same team
        if defender_ulid == attacker_ulid || !defender.is_alive || defender.player_ulid == attacker_team {
            continue;
        }

        // Check range
        if is_in_range(attacker_pos, defender.position, range) {
            enemies.push(defender_ulid.clone());
        }
    }

    enemies
}

#[cfg(test)]
mod tests {
    use super::*;
    use dashmap::DashMap;
    use std::sync::Arc;

    fn create_test_combatant(ulid: Vec<u8>, team: Vec<u8>, pos: (i32, i32)) -> Combatant {
        Combatant {
            ulid: ulid.clone(),
            player_ulid: team,
            position: pos,
            attack_interval: 1.5,
            is_alive: true,
        }
    }

    #[test]
    fn test_find_closest_enemy() {
        let combatants: CombatantMap = Arc::new(DashMap::new());

        let attacker_ulid = vec![1];
        let team_a = vec![100];
        let team_b = vec![200];

        // Add attacker (team A at origin)
        combatants.insert(
            attacker_ulid.clone(),
            create_test_combatant(attacker_ulid.clone(), team_a.clone(), (0, 0)),
        );

        // Add close enemy (team B, distance 1)
        let close_enemy = vec![2];
        combatants.insert(
            close_enemy.clone(),
            create_test_combatant(close_enemy.clone(), team_b.clone(), (1, 0)),
        );

        // Add far enemy (team B, distance 3)
        let far_enemy = vec![3];
        combatants.insert(
            far_enemy.clone(),
            create_test_combatant(far_enemy.clone(), team_b.clone(), (3, 0)),
        );

        // Find closest within range 5
        let result = find_closest_enemy(&attacker_ulid, &combatants, 5);
        assert_eq!(result, Some(close_enemy));
    }

    #[test]
    fn test_no_enemies_in_range() {
        let combatants: CombatantMap = Arc::new(DashMap::new());

        let attacker_ulid = vec![1];
        let team_a = vec![100];
        let team_b = vec![200];

        combatants.insert(
            attacker_ulid.clone(),
            create_test_combatant(attacker_ulid.clone(), team_a.clone(), (0, 0)),
        );

        // Add enemy far away
        let far_enemy = vec![2];
        combatants.insert(
            far_enemy.clone(),
            create_test_combatant(far_enemy.clone(), team_b.clone(), (10, 10)),
        );

        // Find within range 3 (should find nothing)
        let result = find_closest_enemy(&attacker_ulid, &combatants, 3);
        assert_eq!(result, None);
    }
}
