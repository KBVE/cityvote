/// Quadtree for hierarchical spatial partitioning
///
/// A quadtree recursively divides 2D space into four quadrants.
/// Each node can contain entities or subdivide into 4 children.
///
/// Perfect for:
/// - Dynamic insertion/removal (better than K-D tree for this)
/// - Camera frustum culling
/// - Level-of-detail (LOD) rendering
/// - Hierarchical collision detection
///
/// Time complexity:
/// - Insert/Remove: O(log n) average
/// - Query: O(log n + k) where k = results

use crate::config::map as map_config;

/// Rectangle bounds
#[derive(Debug, Clone, Copy)]
pub struct Rect {
    pub x: f32,
    pub y: f32,
    pub width: f32,
    pub height: f32,
}

impl Rect {
    pub fn new(x: f32, y: f32, width: f32, height: f32) -> Self {
        Self { x, y, width, height }
    }

    /// Check if point is inside rectangle
    #[inline]
    pub fn contains_point(&self, x: f32, y: f32) -> bool {
        x >= self.x && x < self.x + self.width &&
        y >= self.y && y < self.y + self.height
    }

    /// Check if rectangles intersect
    #[inline]
    pub fn intersects(&self, other: &Rect) -> bool {
        self.x < other.x + other.width &&
        self.x + self.width > other.x &&
        self.y < other.y + other.height &&
        self.y + self.height > other.y
    }

    /// Check if circle intersects rectangle
    #[inline]
    pub fn intersects_circle(&self, cx: f32, cy: f32, radius: f32) -> bool {
        // Find closest point on rectangle to circle center
        let closest_x = cx.max(self.x).min(self.x + self.width);
        let closest_y = cy.max(self.y).min(self.y + self.height);

        // Check if distance to closest point is within radius
        let dx = cx - closest_x;
        let dy = cy - closest_y;
        (dx * dx + dy * dy) <= (radius * radius)
    }

    /// Get center point
    pub fn center(&self) -> (f32, f32) {
        (self.x + self.width / 2.0, self.y + self.height / 2.0)
    }
}

/// Entity with position
#[derive(Debug, Clone, Copy)]
pub struct Entity {
    pub id: u64,
    pub x: f32,
    pub y: f32,
}

impl Entity {
    pub fn new(id: u64, x: f32, y: f32) -> Self {
        Self { id, x, y }
    }
}

/// Quadtree configuration
pub struct QuadTreeConfig {
    /// Maximum entities per node before subdivision
    pub max_entities: usize,

    /// Maximum depth of tree (prevents infinite subdivision)
    pub max_depth: usize,
}

impl Default for QuadTreeConfig {
    fn default() -> Self {
        Self {
            max_entities: 4,
            max_depth: 8,
        }
    }
}

/// Quadtree node
pub struct QuadTree {
    /// Boundary of this node
    bounds: Rect,

    /// Entities in this node (if leaf)
    entities: Vec<Entity>,

    /// Children nodes (NW, NE, SW, SE)
    children: Option<Box<[QuadTree; 4]>>,

    /// Current depth
    depth: usize,

    /// Configuration
    config: QuadTreeConfig,
}

impl QuadTree {
    /// Create new quadtree with default config
    pub fn new(bounds: Rect) -> Self {
        Self::with_config(bounds, QuadTreeConfig::default())
    }

    /// Create new quadtree with custom config
    pub fn with_config(bounds: Rect, config: QuadTreeConfig) -> Self {
        Self {
            bounds,
            entities: Vec::new(),
            children: None,
            depth: 0,
            config,
        }
    }

    /// Create quadtree for entire map
    pub fn for_map() -> Self {
        let width = (map_config::WIDTH * 32) as f32;
        let height = (map_config::HEIGHT * 32) as f32;
        Self::new(Rect::new(0.0, 0.0, width, height))
    }

    /// Create child node at given depth
    fn create_child(bounds: Rect, config: QuadTreeConfig, depth: usize) -> Self {
        Self {
            bounds,
            entities: Vec::new(),
            children: None,
            depth,
            config,
        }
    }

    /// Subdivide node into 4 quadrants
    fn subdivide(&mut self) {
        let half_width = self.bounds.width / 2.0;
        let half_height = self.bounds.height / 2.0;
        let x = self.bounds.x;
        let y = self.bounds.y;

        // Create 4 children: NW, NE, SW, SE
        self.children = Some(Box::new([
            Self::create_child(
                Rect::new(x, y, half_width, half_height),
                QuadTreeConfig {
                    max_entities: self.config.max_entities,
                    max_depth: self.config.max_depth,
                },
                self.depth + 1,
            ),
            Self::create_child(
                Rect::new(x + half_width, y, half_width, half_height),
                QuadTreeConfig {
                    max_entities: self.config.max_entities,
                    max_depth: self.config.max_depth,
                },
                self.depth + 1,
            ),
            Self::create_child(
                Rect::new(x, y + half_height, half_width, half_height),
                QuadTreeConfig {
                    max_entities: self.config.max_entities,
                    max_depth: self.config.max_depth,
                },
                self.depth + 1,
            ),
            Self::create_child(
                Rect::new(x + half_width, y + half_height, half_width, half_height),
                QuadTreeConfig {
                    max_entities: self.config.max_entities,
                    max_depth: self.config.max_depth,
                },
                self.depth + 1,
            ),
        ]));

        // Move existing entities to children
        let entities = std::mem::take(&mut self.entities);
        for entity in entities {
            self.insert_into_children(entity);
        }
    }

    /// Insert entity into appropriate child
    fn insert_into_children(&mut self, entity: Entity) {
        if let Some(children) = &mut self.children {
            for child in children.iter_mut() {
                if child.bounds.contains_point(entity.x, entity.y) {
                    child.insert(entity);
                    return;
                }
            }
        }
        // Fallback: keep in this node if no child contains it
        self.entities.push(entity);
    }

    /// Insert entity into quadtree
    pub fn insert(&mut self, entity: Entity) {
        // Check if entity is within bounds
        if !self.bounds.contains_point(entity.x, entity.y) {
            return;
        }

        // If we have children, insert into appropriate child
        if self.children.is_some() {
            self.insert_into_children(entity);
            return;
        }

        // Add to this node
        self.entities.push(entity);

        // Check if we need to subdivide
        if self.entities.len() > self.config.max_entities && self.depth < self.config.max_depth {
            self.subdivide();
        }
    }

    /// Remove entity by ID
    pub fn remove(&mut self, entity_id: u64) -> bool {
        // Try to remove from this node
        if let Some(index) = self.entities.iter().position(|e| e.id == entity_id) {
            self.entities.remove(index);
            return true;
        }

        // Try children
        if let Some(children) = &mut self.children {
            for child in children.iter_mut() {
                if child.remove(entity_id) {
                    return true;
                }
            }
        }

        false
    }

    /// Query entities within rectangle
    pub fn query_rect(&self, rect: &Rect, results: &mut Vec<Entity>) {
        // Check if boundary intersects search rect
        if !self.bounds.intersects(rect) {
            return;
        }

        // Add entities from this node that are in range
        for entity in &self.entities {
            if rect.contains_point(entity.x, entity.y) {
                results.push(*entity);
            }
        }

        // Recursively check children
        if let Some(children) = &self.children {
            for child in children.iter() {
                child.query_rect(rect, results);
            }
        }
    }

    /// Query entities within radius of a point
    pub fn query_radius(&self, x: f32, y: f32, radius: f32, results: &mut Vec<Entity>) {
        // Check if boundary intersects search circle
        if !self.bounds.intersects_circle(x, y, radius) {
            return;
        }

        let radius_squared = radius * radius;

        // Check entities in this node
        for entity in &self.entities {
            let dx = entity.x - x;
            let dy = entity.y - y;
            if dx * dx + dy * dy <= radius_squared {
                results.push(*entity);
            }
        }

        // Recursively check children
        if let Some(children) = &self.children {
            for child in children.iter() {
                child.query_radius(x, y, radius, results);
            }
        }
    }

    /// Find nearest entity to a point
    pub fn find_nearest(&self, x: f32, y: f32) -> Option<Entity> {
        let mut best: Option<Entity> = None;
        let mut best_dist_sq = f32::MAX;

        self.find_nearest_recursive(x, y, &mut best, &mut best_dist_sq);
        best
    }

    /// Recursive nearest neighbor search
    fn find_nearest_recursive(&self, x: f32, y: f32, best: &mut Option<Entity>, best_dist_sq: &mut f32) {
        // Check if this node could contain closer entity
        let (cx, cy) = self.bounds.center();
        let node_dist_sq = (x - cx) * (x - cx) + (y - cy) * (y - cy);
        let node_radius = (self.bounds.width * self.bounds.width + self.bounds.height * self.bounds.height).sqrt() / 2.0;

        if node_dist_sq - node_radius * node_radius > *best_dist_sq {
            return; // Node is too far
        }

        // Check entities in this node
        for entity in &self.entities {
            let dx = entity.x - x;
            let dy = entity.y - y;
            let dist_sq = dx * dx + dy * dy;

            if dist_sq < *best_dist_sq {
                *best_dist_sq = dist_sq;
                *best = Some(*entity);
            }
        }

        // Recursively check children (sorted by distance for early termination)
        if let Some(children) = &self.children {
            // Calculate distances to each child's center
            let mut child_dists: Vec<(usize, f32)> = children
                .iter()
                .enumerate()
                .map(|(i, child)| {
                    let (child_cx, child_cy) = child.bounds.center();
                    let dist_sq = (x - child_cx) * (x - child_cx) + (y - child_cy) * (y - child_cy);
                    (i, dist_sq)
                })
                .collect();

            // Sort by distance
            child_dists.sort_by(|a, b| a.1.partial_cmp(&b.1).unwrap());

            // Search children in order of distance
            for (idx, _) in child_dists {
                children[idx].find_nearest_recursive(x, y, best, best_dist_sq);
            }
        }
    }

    /// Clear all entities
    pub fn clear(&mut self) {
        self.entities.clear();
        self.children = None;
    }

    /// Get total entity count (including children)
    pub fn count(&self) -> usize {
        let mut total = self.entities.len();
        if let Some(children) = &self.children {
            for child in children.iter() {
                total += child.count();
            }
        }
        total
    }

    /// Get tree statistics
    pub fn stats(&self) -> QuadTreeStats {
        let mut stats = QuadTreeStats {
            total_nodes: 1,
            leaf_nodes: if self.children.is_none() { 1 } else { 0 },
            total_entities: self.entities.len(),
            max_depth: self.depth,
            entities_at_depth: vec![0; self.config.max_depth + 1],
        };

        stats.entities_at_depth[self.depth] = self.entities.len();

        if let Some(children) = &self.children {
            for child in children.iter() {
                let child_stats = child.stats();
                stats.total_nodes += child_stats.total_nodes;
                stats.leaf_nodes += child_stats.leaf_nodes;
                stats.total_entities += child_stats.total_entities;
                stats.max_depth = stats.max_depth.max(child_stats.max_depth);

                for (depth, count) in child_stats.entities_at_depth.iter().enumerate() {
                    stats.entities_at_depth[depth] += count;
                }
            }
        }

        stats
    }
}

/// Statistics about quadtree structure
#[derive(Debug, Clone)]
pub struct QuadTreeStats {
    pub total_nodes: usize,
    pub leaf_nodes: usize,
    pub total_entities: usize,
    pub max_depth: usize,
    pub entities_at_depth: Vec<usize>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_quadtree_insert_query() {
        let mut tree = QuadTree::new(Rect::new(0.0, 0.0, 100.0, 100.0));

        tree.insert(Entity::new(1, 25.0, 25.0));
        tree.insert(Entity::new(2, 75.0, 75.0));
        tree.insert(Entity::new(3, 50.0, 50.0));

        let mut results = Vec::new();
        tree.query_rect(&Rect::new(0.0, 0.0, 50.0, 50.0), &mut results);

        assert_eq!(results.len(), 2); // Entities 1 and 3
    }

    #[test]
    fn test_quadtree_radius_query() {
        let mut tree = QuadTree::new(Rect::new(0.0, 0.0, 100.0, 100.0));

        tree.insert(Entity::new(1, 50.0, 50.0));
        tree.insert(Entity::new(2, 55.0, 55.0));
        tree.insert(Entity::new(3, 90.0, 90.0));

        let mut results = Vec::new();
        tree.query_radius(50.0, 50.0, 10.0, &mut results);

        assert_eq!(results.len(), 2); // Entities 1 and 2
    }
}
