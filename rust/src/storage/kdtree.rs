/// K-D Tree for fast nearest-neighbor queries
///
/// A K-D tree (k-dimensional tree) is a space-partitioning data structure
/// for organizing points in k-dimensional space. For 2D games, k=2.
///
/// Perfect for:
/// - Finding K nearest neighbors
/// - Range searches
/// - AI targeting (find closest enemy)
/// - Optimized pathfinding endpoints
///
/// Time complexity:
/// - Build: O(n log n)
/// - Nearest neighbor: O(log n) average, O(n) worst case
/// - K nearest: O(k log n) average

use std::cmp::Ordering;

/// 2D point with associated entity ID
#[derive(Debug, Clone, Copy)]
pub struct Point2D {
    pub x: f32,
    pub y: f32,
    pub entity_id: u64,
}

impl Point2D {
    pub fn new(x: f32, y: f32, entity_id: u64) -> Self {
        Self { x, y, entity_id }
    }

    /// Calculate squared distance to another point (avoid sqrt for performance)
    #[inline]
    pub fn distance_squared(&self, other: &Point2D) -> f32 {
        let dx = self.x - other.x;
        let dy = self.y - other.y;
        dx * dx + dy * dy
    }

    /// Calculate actual distance to another point
    #[inline]
    pub fn distance(&self, other: &Point2D) -> f32 {
        self.distance_squared(other).sqrt()
    }
}

/// K-D Tree node
#[derive(Debug, Clone)]
enum KDNode {
    Leaf {
        point: Point2D,
    },
    Branch {
        point: Point2D,
        axis: usize,        // 0 = x-axis, 1 = y-axis
        left: Box<KDNode>,
        right: Box<KDNode>,
    },
}

/// Helper struct for K-nearest heap
#[derive(Clone, Copy)]
struct HeapEntry {
    point: Point2D,
    distance: f32,
}

impl PartialEq for HeapEntry {
    fn eq(&self, other: &Self) -> bool {
        self.distance == other.distance
    }
}

impl Eq for HeapEntry {}

impl PartialOrd for HeapEntry {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        other.distance.partial_cmp(&self.distance) // Reverse for min-heap
    }
}

impl Ord for HeapEntry {
    fn cmp(&self, other: &Self) -> Ordering {
        self.partial_cmp(other).unwrap_or(Ordering::Equal)
    }
}

/// K-D Tree for 2D spatial queries
pub struct KDTree {
    root: Option<Box<KDNode>>,
    size: usize,
}

impl KDTree {
    /// Create an empty K-D tree
    pub fn new() -> Self {
        Self {
            root: None,
            size: 0,
        }
    }

    /// Build K-D tree from a slice of points
    pub fn build(mut points: Vec<Point2D>) -> Self {
        let size = points.len();
        let root = if points.is_empty() {
            None
        } else {
            Some(Box::new(Self::build_recursive(&mut points, 0)))
        };

        Self { root, size }
    }

    /// Recursive tree building
    fn build_recursive(points: &mut [Point2D], depth: usize) -> KDNode {
        if points.is_empty() {
            panic!("Cannot build node from empty points");
        }

        if points.len() == 1 {
            return KDNode::Leaf {
                point: points[0],
            };
        }

        // Alternate between x and y axis
        let axis = depth % 2;

        // Sort by current axis
        points.sort_by(|a, b| {
            let val_a = if axis == 0 { a.x } else { a.y };
            let val_b = if axis == 0 { b.x } else { b.y };
            val_a.partial_cmp(&val_b).unwrap_or(Ordering::Equal)
        });

        // Find median
        let median = points.len() / 2;
        let point = points[median];

        // Split into left and right subtrees
        let (left_points, right_points) = points.split_at_mut(median);
        let right_points = &mut right_points[1..]; // Skip median point

        KDNode::Branch {
            point,
            axis,
            left: if left_points.is_empty() {
                Box::new(KDNode::Leaf { point })
            } else {
                Box::new(Self::build_recursive(left_points, depth + 1))
            },
            right: if right_points.is_empty() {
                Box::new(KDNode::Leaf { point })
            } else {
                Box::new(Self::build_recursive(right_points, depth + 1))
            },
        }
    }

    /// Find nearest neighbor to target point
    pub fn nearest(&self, target: &Point2D) -> Option<Point2D> {
        self.root.as_ref().map(|root| {
            let mut best = None;
            let mut best_dist = f32::MAX;
            Self::nearest_recursive(root, target, &mut best, &mut best_dist);
            best.unwrap()
        })
    }

    /// Recursive nearest neighbor search
    fn nearest_recursive(
        node: &KDNode,
        target: &Point2D,
        best: &mut Option<Point2D>,
        best_dist: &mut f32,
    ) {
        match node {
            KDNode::Leaf { point } => {
                let dist = target.distance_squared(point);
                if dist < *best_dist {
                    *best_dist = dist;
                    *best = Some(*point);
                }
            }
            KDNode::Branch { point, axis, left, right } => {
                // Check current point
                let dist = target.distance_squared(point);
                if dist < *best_dist {
                    *best_dist = dist;
                    *best = Some(*point);
                }

                // Determine which side to search first
                let target_val = if *axis == 0 { target.x } else { target.y };
                let split_val = if *axis == 0 { point.x } else { point.y };

                let (near, far) = if target_val < split_val {
                    (left, right)
                } else {
                    (right, left)
                };

                // Search near side
                Self::nearest_recursive(near, target, best, best_dist);

                // Check if we need to search far side
                let axis_dist = (target_val - split_val).abs();
                if axis_dist * axis_dist < *best_dist {
                    Self::nearest_recursive(far, target, best, best_dist);
                }
            }
        }
    }

    /// Find K nearest neighbors
    pub fn k_nearest(&self, target: &Point2D, k: usize) -> Vec<Point2D> {
        if k == 0 || self.root.is_none() {
            return Vec::new();
        }

        let mut heap = std::collections::BinaryHeap::new();
        Self::k_nearest_recursive(self.root.as_ref().unwrap(), target, k, &mut heap);

        // Extract sorted results
        heap.into_sorted_vec()
            .into_iter()
            .map(|entry| entry.point)
            .collect()
    }

    /// Recursive K-nearest search
    fn k_nearest_recursive(
        node: &KDNode,
        target: &Point2D,
        k: usize,
        heap: &mut std::collections::BinaryHeap<HeapEntry>,
    ) {
        match node {
            KDNode::Leaf { point } => {
                let dist = target.distance_squared(point);
                if heap.len() < k {
                    heap.push(HeapEntry { point: *point, distance: dist });
                } else if let Some(worst) = heap.peek() {
                    if dist < worst.distance {
                        heap.pop();
                        heap.push(HeapEntry { point: *point, distance: dist });
                    }
                }
            }
            KDNode::Branch { point, axis, left, right } => {
                // Check current point
                let dist = target.distance_squared(point);
                if heap.len() < k {
                    heap.push(HeapEntry { point: *point, distance: dist });
                } else if let Some(worst) = heap.peek() {
                    if dist < worst.distance {
                        heap.pop();
                        heap.push(HeapEntry { point: *point, distance: dist });
                    }
                }

                // Determine search order
                let target_val = if *axis == 0 { target.x } else { target.y };
                let split_val = if *axis == 0 { point.x } else { point.y };

                let (near, far) = if target_val < split_val {
                    (left, right)
                } else {
                    (right, left)
                };

                // Search near side
                Self::k_nearest_recursive(near, target, k, heap);

                // Check if we need to search far side
                let axis_dist = (target_val - split_val).abs();
                if heap.len() < k || (axis_dist * axis_dist) < heap.peek().unwrap().distance {
                    Self::k_nearest_recursive(far, target, k, heap);
                }
            }
        }
    }

    /// Find all points within radius of target
    pub fn range_search(&self, target: &Point2D, radius: f32) -> Vec<Point2D> {
        let mut results = Vec::new();
        let radius_squared = radius * radius;

        if let Some(root) = &self.root {
            Self::range_search_recursive(root, target, radius_squared, &mut results);
        }

        results
    }

    /// Recursive range search
    fn range_search_recursive(
        node: &KDNode,
        target: &Point2D,
        radius_squared: f32,
        results: &mut Vec<Point2D>,
    ) {
        match node {
            KDNode::Leaf { point } => {
                if target.distance_squared(point) <= radius_squared {
                    results.push(*point);
                }
            }
            KDNode::Branch { point, axis, left, right } => {
                // Check current point
                if target.distance_squared(point) <= radius_squared {
                    results.push(*point);
                }

                // Determine which sides to search
                let target_val = if *axis == 0 { target.x } else { target.y };
                let split_val = if *axis == 0 { point.x } else { point.y };
                let axis_dist = (target_val - split_val).abs();

                // Always search the near side
                let (near, far) = if target_val < split_val {
                    (left, right)
                } else {
                    (right, left)
                };

                Self::range_search_recursive(near, target, radius_squared, results);

                // Search far side if circle intersects splitting plane
                if axis_dist * axis_dist <= radius_squared {
                    Self::range_search_recursive(far, target, radius_squared, results);
                }
            }
        }
    }

    /// Get number of points in tree
    pub fn size(&self) -> usize {
        self.size
    }

    /// Check if tree is empty
    pub fn is_empty(&self) -> bool {
        self.root.is_none()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_kdtree_nearest() {
        let points = vec![
            Point2D::new(2.0, 3.0, 1),
            Point2D::new(5.0, 4.0, 2),
            Point2D::new(9.0, 6.0, 3),
            Point2D::new(4.0, 7.0, 4),
            Point2D::new(8.0, 1.0, 5),
        ];

        let tree = KDTree::build(points);
        let target = Point2D::new(5.0, 5.0, 0);
        let nearest = tree.nearest(&target).unwrap();

        assert_eq!(nearest.entity_id, 2); // Point at (5, 4)
    }

    #[test]
    fn test_kdtree_k_nearest() {
        let points = vec![
            Point2D::new(1.0, 1.0, 1),
            Point2D::new(2.0, 2.0, 2),
            Point2D::new(3.0, 3.0, 3),
            Point2D::new(10.0, 10.0, 4),
        ];

        let tree = KDTree::build(points);
        let target = Point2D::new(0.0, 0.0, 0);
        let nearest = tree.k_nearest(&target, 2);

        assert_eq!(nearest.len(), 2);
        assert_eq!(nearest[0].entity_id, 1);
        assert_eq!(nearest[1].entity_id, 2);
    }
}
