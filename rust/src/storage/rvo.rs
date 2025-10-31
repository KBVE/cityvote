/// Reciprocal Velocity Obstacles (RVO) for collision avoidance
///
/// RVO is a local collision avoidance algorithm where each agent
/// independently computes a collision-free velocity based on the
/// positions and velocities of nearby agents.
///
/// Perfect for:
/// - Smooth crowd movement (units don't overlap)
/// - Local obstacle avoidance
/// - Formation maintenance
/// - Natural-looking agent behavior
///
/// Key concept:
/// - Each agent assumes others will also avoid collision
/// - Results in "reciprocal" avoidance (both agents move)
/// - Much smoother than traditional collision detection
///
/// Time complexity:
/// - Per agent: O(n) where n = nearby agents (typically small with spatial partitioning)

use std::f32::consts::PI;

/// 2D Vector for positions and velocities
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Vec2 {
    pub x: f32,
    pub y: f32,
}

impl Vec2 {
    pub const ZERO: Vec2 = Vec2 { x: 0.0, y: 0.0 };

    pub fn new(x: f32, y: f32) -> Self {
        Self { x, y }
    }

    /// Calculate length (magnitude) of vector
    #[inline]
    pub fn length(&self) -> f32 {
        (self.x * self.x + self.y * self.y).sqrt()
    }

    /// Calculate squared length (faster, avoids sqrt)
    #[inline]
    pub fn length_squared(&self) -> f32 {
        self.x * self.x + self.y * self.y
    }

    /// Normalize vector (make length = 1)
    #[inline]
    pub fn normalize(&self) -> Vec2 {
        let len = self.length();
        if len > 0.0001 {
            Vec2 {
                x: self.x / len,
                y: self.y / len,
            }
        } else {
            Vec2::ZERO
        }
    }

    /// Dot product
    #[inline]
    pub fn dot(&self, other: &Vec2) -> f32 {
        self.x * other.x + self.y * other.y
    }

    /// Calculate distance to another vector
    #[inline]
    pub fn distance_to(&self, other: &Vec2) -> f32 {
        let dx = self.x - other.x;
        let dy = self.y - other.y;
        (dx * dx + dy * dy).sqrt()
    }

    /// Scalar multiplication
    #[inline]
    pub fn scale(&self, scalar: f32) -> Vec2 {
        Vec2 {
            x: self.x * scalar,
            y: self.y * scalar,
        }
    }

    /// Add vectors
    #[inline]
    pub fn add(&self, other: &Vec2) -> Vec2 {
        Vec2 {
            x: self.x + other.x,
            y: self.y + other.y,
        }
    }

    /// Subtract vectors
    #[inline]
    pub fn sub(&self, other: &Vec2) -> Vec2 {
        Vec2 {
            x: self.x - other.x,
            y: self.y - other.y,
        }
    }

    /// Linear interpolation
    #[inline]
    pub fn lerp(&self, other: &Vec2, t: f32) -> Vec2 {
        Vec2 {
            x: self.x + (other.x - self.x) * t,
            y: self.y + (other.y - self.y) * t,
        }
    }

    /// Clamp vector length to maximum
    pub fn clamp_length(&self, max_length: f32) -> Vec2 {
        let len = self.length();
        if len > max_length {
            self.scale(max_length / len)
        } else {
            *self
        }
    }
}

/// Agent for RVO simulation
#[derive(Debug, Clone)]
pub struct Agent {
    /// Unique ID
    pub id: u64,

    /// Current position
    pub position: Vec2,

    /// Current velocity
    pub velocity: Vec2,

    /// Preferred velocity (where agent wants to go)
    pub preferred_velocity: Vec2,

    /// Radius (for collision detection)
    pub radius: f32,

    /// Maximum speed
    pub max_speed: f32,

    /// Time horizon for collision prediction (seconds)
    pub time_horizon: f32,

    /// Maximum number of neighbors to consider
    pub max_neighbors: usize,
}

impl Agent {
    /// Create new agent
    pub fn new(id: u64, position: Vec2, radius: f32, max_speed: f32) -> Self {
        Self {
            id,
            position,
            velocity: Vec2::ZERO,
            preferred_velocity: Vec2::ZERO,
            radius,
            max_speed,
            time_horizon: 2.0,      // 2 seconds look-ahead
            max_neighbors: 10,      // Consider 10 nearest agents
        }
    }

    /// Set preferred velocity (direction agent wants to move)
    pub fn set_preferred_velocity(&mut self, velocity: Vec2) {
        self.preferred_velocity = velocity.clamp_length(self.max_speed);
    }

    /// Compute new velocity avoiding other agents (RVO algorithm)
    pub fn compute_new_velocity(&self, neighbors: &[&Agent]) -> Vec2 {
        if neighbors.is_empty() {
            return self.preferred_velocity;
        }

        // Sample candidate velocities in a grid around preferred velocity
        let num_samples = 50;
        let mut best_velocity = self.preferred_velocity;
        let mut best_penalty = f32::MAX;

        for i in 0..num_samples {
            // Create candidate velocity by perturbing preferred velocity
            let angle = (i as f32 / num_samples as f32) * 2.0 * PI;
            let radius = self.max_speed * ((i % 5) as f32 / 5.0);

            let candidate = Vec2 {
                x: self.preferred_velocity.x + radius * angle.cos(),
                y: self.preferred_velocity.y + radius * angle.sin(),
            };

            // Clamp to max speed
            let candidate = candidate.clamp_length(self.max_speed);

            // Calculate penalty for this velocity
            let penalty = self.compute_velocity_penalty(&candidate, neighbors);

            if penalty < best_penalty {
                best_penalty = penalty;
                best_velocity = candidate;
            }
        }

        best_velocity
    }

    /// Compute penalty for a candidate velocity
    fn compute_velocity_penalty(&self, candidate: &Vec2, neighbors: &[&Agent]) -> f32 {
        let mut penalty = 0.0;

        // Penalty for deviating from preferred velocity
        let deviation = self.preferred_velocity.sub(candidate).length();
        penalty += deviation * 0.5;

        // Penalty for potential collisions
        for neighbor in neighbors {
            let time_to_collision = self.time_to_collision(candidate, neighbor);

            if time_to_collision < self.time_horizon {
                // Penalize based on how soon collision would occur
                let urgency = 1.0 - (time_to_collision / self.time_horizon);
                penalty += urgency * 10.0;
            }
        }

        penalty
    }

    /// Calculate time to collision with another agent
    fn time_to_collision(&self, velocity: &Vec2, other: &Agent) -> f32 {
        // Relative position and velocity
        let rel_pos = other.position.sub(&self.position);
        let rel_vel = velocity.sub(&other.velocity);

        // Combined radius
        let combined_radius = self.radius + other.radius;

        // If relative velocity is too small, no collision
        let rel_speed_sq = rel_vel.length_squared();
        if rel_speed_sq < 0.0001 {
            return f32::MAX;
        }

        // Time to closest approach
        let t = -rel_pos.dot(&rel_vel) / rel_speed_sq;

        if t < 0.0 {
            return f32::MAX; // Moving away
        }

        // Position at closest approach
        let closest_pos = rel_pos.add(&rel_vel.scale(t));
        let closest_dist_sq = closest_pos.length_squared();

        // Check if collision occurs
        if closest_dist_sq < combined_radius * combined_radius {
            t
        } else {
            f32::MAX
        }
    }

    /// Update agent position based on current velocity and delta time
    pub fn update(&mut self, delta_time: f32) {
        self.position = self.position.add(&self.velocity.scale(delta_time));
    }
}

/// RVO Simulator manages multiple agents
pub struct RVOSimulator {
    /// All agents in simulation
    agents: std::collections::HashMap<u64, Agent>,

    /// Default agent parameters
    pub default_radius: f32,
    pub default_max_speed: f32,
    pub default_time_horizon: f32,
}

impl RVOSimulator {
    /// Create new RVO simulator
    pub fn new() -> Self {
        Self {
            agents: std::collections::HashMap::new(),
            default_radius: 16.0,       // 16 pixels radius
            default_max_speed: 100.0,   // 100 pixels/second
            default_time_horizon: 2.0,  // 2 seconds look-ahead
        }
    }

    /// Add agent to simulation
    pub fn add_agent(&mut self, id: u64, position: Vec2) -> &mut Agent {
        let agent = Agent::new(id, position, self.default_radius, self.default_max_speed);
        self.agents.insert(id, agent);
        self.agents.get_mut(&id).unwrap()
    }

    /// Remove agent from simulation
    pub fn remove_agent(&mut self, id: u64) {
        self.agents.remove(&id);
    }

    /// Get agent by ID
    pub fn get_agent(&self, id: u64) -> Option<&Agent> {
        self.agents.get(&id)
    }

    /// Get mutable agent by ID
    pub fn get_agent_mut(&mut self, id: u64) -> Option<&mut Agent> {
        self.agents.get_mut(&id)
    }

    /// Update all agents' velocities using RVO
    pub fn compute_velocities(&mut self) {
        // For each agent, find neighbors and compute new velocity
        let agent_ids: Vec<u64> = self.agents.keys().copied().collect();

        let mut new_velocities = std::collections::HashMap::new();

        for agent_id in &agent_ids {
            let agent = &self.agents[agent_id];

            // Find nearby agents (simple O(n) search, use spatial hash in production)
            let mut neighbors = Vec::new();
            for other_id in &agent_ids {
                if other_id == agent_id {
                    continue;
                }

                let other = &self.agents[other_id];
                let dist = agent.position.distance_to(&other.position);

                // Consider agents within time_horizon * max_speed distance
                let max_dist = agent.time_horizon * agent.max_speed;
                if dist < max_dist && neighbors.len() < agent.max_neighbors {
                    neighbors.push(other);
                }
            }

            // Compute new velocity
            let new_velocity = agent.compute_new_velocity(&neighbors);
            new_velocities.insert(*agent_id, new_velocity);
        }

        // Apply new velocities
        for (agent_id, new_velocity) in new_velocities {
            if let Some(agent) = self.agents.get_mut(&agent_id) {
                agent.velocity = new_velocity;
            }
        }
    }

    /// Update all agents' positions
    pub fn update(&mut self, delta_time: f32) {
        for agent in self.agents.values_mut() {
            agent.update(delta_time);
        }
    }

    /// Step simulation (compute velocities + update positions)
    pub fn step(&mut self, delta_time: f32) {
        self.compute_velocities();
        self.update(delta_time);
    }

    /// Get number of agents
    pub fn agent_count(&self) -> usize {
        self.agents.len()
    }

    /// Clear all agents
    pub fn clear(&mut self) {
        self.agents.clear();
    }
}

/// Global RVO simulator (thread-safe)
use parking_lot::RwLock;
use std::sync::Arc;

static RVO_SIMULATOR: once_cell::sync::Lazy<Arc<RwLock<RVOSimulator>>> =
    once_cell::sync::Lazy::new(|| Arc::new(RwLock::new(RVOSimulator::new())));

/// Get global RVO simulator
pub fn get_simulator() -> Arc<RwLock<RVOSimulator>> {
    Arc::clone(&RVO_SIMULATOR)
}

/// Add agent to global simulator
pub fn add_agent(id: u64, position: Vec2) {
    let mut sim = RVO_SIMULATOR.write();
    sim.add_agent(id, position);
}

/// Set agent preferred velocity
pub fn set_preferred_velocity(id: u64, velocity: Vec2) {
    let mut sim = RVO_SIMULATOR.write();
    if let Some(agent) = sim.get_agent_mut(id) {
        agent.set_preferred_velocity(velocity);
    }
}

/// Step simulation
pub fn step_simulation(delta_time: f32) {
    let mut sim = RVO_SIMULATOR.write();
    sim.step(delta_time);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_vec2_operations() {
        let v1 = Vec2::new(3.0, 4.0);
        assert!((v1.length() - 5.0).abs() < 0.001);

        let normalized = v1.normalize();
        assert!((normalized.length() - 1.0).abs() < 0.001);
    }

    #[test]
    fn test_agent_collision_avoidance() {
        let agent1 = Agent::new(1, Vec2::new(0.0, 0.0), 10.0, 50.0);
        let mut agent2 = Agent::new(2, Vec2::new(100.0, 0.0), 10.0, 50.0);

        // Agent2 wants to move toward agent1
        agent2.set_preferred_velocity(Vec2::new(-50.0, 0.0));

        // Compute new velocity (should avoid collision)
        let neighbors = vec![&agent1];
        let new_velocity = agent2.compute_new_velocity(&neighbors);

        // New velocity should deviate from straight path
        assert!(new_velocity.y.abs() > 1.0); // Should have y-component to avoid
    }
}
