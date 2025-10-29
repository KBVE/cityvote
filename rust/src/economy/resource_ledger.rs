use dashmap::DashMap;
use once_cell::sync::Lazy;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread;
use crossbeam_queue::SegQueue;

/// Resource types (must match GDScript enum)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
#[repr(i32)]
pub enum ResourceType {
    Gold = 0,
    Food = 1,
    Labor = 2,
    Faith = 3,
}

impl ResourceType {
    pub fn from_i32(value: i32) -> Option<Self> {
        match value {
            0 => Some(ResourceType::Gold),
            1 => Some(ResourceType::Food),
            2 => Some(ResourceType::Labor),
            3 => Some(ResourceType::Faith),
            _ => None,
        }
    }
}

/// Resource data for a single resource type
#[derive(Debug, Clone)]
pub struct ResourceData {
    pub current: f32,
    pub cap: f32,
    pub rate: f32, // net production per second (can be negative)
}

impl ResourceData {
    pub fn new(initial: f32, cap: f32) -> Self {
        Self {
            current: initial,
            cap,
            rate: 0.0,
        }
    }
}

/// Producer data tracked by ULID
#[derive(Debug, Clone)]
pub struct ProducerData {
    pub resource_type: ResourceType,
    pub rate_per_sec: f32,
    pub active: bool,
}

/// Consumer data tracked by ULID
#[derive(Debug, Clone)]
pub struct ConsumerData {
    pub resource_type: ResourceType,
    pub rate_per_sec: f32,
    pub active: bool,
}

/// Global resource ledger (thread-safe)
static RESOURCE_LEDGER: Lazy<Arc<DashMap<ResourceType, ResourceData>>> = Lazy::new(|| {
    let ledger = DashMap::new();

    // Initialize with default values
    // All resources use f32::MAX for effectively unlimited caps
    ledger.insert(ResourceType::Gold, ResourceData::new(100.0, f32::MAX));
    ledger.insert(ResourceType::Food, ResourceData::new(50.0, f32::MAX));
    ledger.insert(ResourceType::Labor, ResourceData::new(10.0, f32::MAX));
    ledger.insert(ResourceType::Faith, ResourceData::new(0.0, f32::MAX));

    Arc::new(ledger)
});

/// Global producers registry (ULID -> ProducerData)
static PRODUCERS: Lazy<Arc<DashMap<Vec<u8>, ProducerData>>> =
    Lazy::new(|| Arc::new(DashMap::new()));

/// Global consumers registry (ULID -> ConsumerData)
static CONSUMERS: Lazy<Arc<DashMap<Vec<u8>, ConsumerData>>> =
    Lazy::new(|| Arc::new(DashMap::new()));

/// Tick request structure
#[derive(Debug, Clone)]
pub struct TickRequest {
    pub delta_s: f32,
}

/// Tick result structure (resource changes)
#[derive(Debug, Clone)]
pub struct TickResult {
    pub changes: Vec<(ResourceType, f32, f32)>, // (type, current, cap)
}

/// Tick request queue (GDScript -> Worker thread)
static TICK_REQUESTS: Lazy<Arc<SegQueue<TickRequest>>> = Lazy::new(|| Arc::new(SegQueue::new()));

/// Tick result queue (Worker thread -> GDScript)
static TICK_RESULTS: Lazy<Arc<SegQueue<TickResult>>> = Lazy::new(|| Arc::new(SegQueue::new()));

/// Worker thread running flag
static WORKER_RUNNING: AtomicBool = AtomicBool::new(false);

/// Initialize the resource ledger and start worker thread (called on startup)
pub fn initialize() {
    // Force initialization of lazy statics
    let _ = &*RESOURCE_LEDGER;
    let _ = &*PRODUCERS;
    let _ = &*CONSUMERS;
    let _ = &*TICK_REQUESTS;
    let _ = &*TICK_RESULTS;

    // Start worker thread if not already running
    if !WORKER_RUNNING.swap(true, Ordering::Relaxed) {
        thread::spawn(|| {
            economy_worker_thread();
        });
    }
}

/// Worker thread for economy ticks (runs in background)
fn economy_worker_thread() {
    loop {
        if !WORKER_RUNNING.load(Ordering::Relaxed) {
            break;
        }

        // Process tick requests
        if let Some(request) = TICK_REQUESTS.pop() {
            let changes = tick_internal(request.delta_s);
            TICK_RESULTS.push(TickResult { changes });
        } else {
            // No requests, sleep briefly to avoid busy-waiting
            thread::sleep(std::time::Duration::from_millis(10));
        }
    }
}

/// Shutdown worker thread
pub fn shutdown() {
    WORKER_RUNNING.store(false, Ordering::Relaxed);
}

/// Get current amount of a resource
pub fn get_current(resource_type: ResourceType) -> f32 {
    RESOURCE_LEDGER
        .get(&resource_type)
        .map(|r| r.current)
        .unwrap_or(0.0)
}

/// Get cap of a resource
pub fn get_cap(resource_type: ResourceType) -> f32 {
    RESOURCE_LEDGER
        .get(&resource_type)
        .map(|r| r.cap)
        .unwrap_or(0.0)
}

/// Get net rate of a resource
pub fn get_rate(resource_type: ResourceType) -> f32 {
    RESOURCE_LEDGER
        .get(&resource_type)
        .map(|r| r.rate)
        .unwrap_or(0.0)
}

/// Set the cap for a resource
pub fn set_cap(resource_type: ResourceType, cap: f32) {
    if let Some(mut entry) = RESOURCE_LEDGER.get_mut(&resource_type) {
        entry.cap = cap.max(0.0);
        // Clamp current to new cap
        entry.current = entry.current.min(entry.cap);
    }
}

/// Set the current amount (clamped to [0, cap])
pub fn set_current(resource_type: ResourceType, amount: f32) {
    if let Some(mut entry) = RESOURCE_LEDGER.get_mut(&resource_type) {
        entry.current = amount.clamp(0.0, entry.cap);
    }
}

/// Add to current amount (clamped to [0, cap])
pub fn add(resource_type: ResourceType, amount: f32) {
    if amount == 0.0 {
        return;
    }

    if let Some(mut entry) = RESOURCE_LEDGER.get_mut(&resource_type) {
        entry.current = (entry.current + amount).clamp(0.0, entry.cap);
    }
}

/// Check if we can spend a cost (multiple resources)
/// Cost is represented as Vec<(ResourceType, f32)>
pub fn can_spend(cost: &[(ResourceType, f32)]) -> bool {
    for (resource_type, amount) in cost {
        if get_current(*resource_type) < *amount {
            return false;
        }
    }
    true
}

/// Spend resources (returns false if not enough)
pub fn spend(cost: &[(ResourceType, f32)]) -> bool {
    // Check first
    if !can_spend(cost) {
        return false;
    }

    // Spend atomically
    for (resource_type, amount) in cost {
        if let Some(mut entry) = RESOURCE_LEDGER.get_mut(resource_type) {
            entry.current -= amount;
        }
    }

    true
}

/// Register a producer (returns ULID for future reference)
pub fn register_producer(ulid: Vec<u8>, resource_type: ResourceType, rate_per_sec: f32, active: bool) {
    PRODUCERS.insert(ulid, ProducerData {
        resource_type,
        rate_per_sec,
        active,
    });
}

/// Register a consumer (returns ULID for future reference)
pub fn register_consumer(ulid: Vec<u8>, resource_type: ResourceType, rate_per_sec: f32, active: bool) {
    CONSUMERS.insert(ulid, ConsumerData {
        resource_type,
        rate_per_sec,
        active,
    });
}

/// Set producer active state
pub fn set_producer_active(ulid: &[u8], active: bool) {
    if let Some(mut producer) = PRODUCERS.get_mut(ulid) {
        producer.active = active;
    }
}

/// Set consumer active state
pub fn set_consumer_active(ulid: &[u8], active: bool) {
    if let Some(mut consumer) = CONSUMERS.get_mut(ulid) {
        consumer.active = active;
    }
}

/// Remove a producer
pub fn remove_producer(ulid: &[u8]) {
    PRODUCERS.remove(ulid);
}

/// Remove a consumer
pub fn remove_consumer(ulid: &[u8]) {
    CONSUMERS.remove(ulid);
}

/// Recalculate net rates for all resources based on active producers/consumers
pub fn recalculate_rates() {
    // Reset all rates to 0
    for mut entry in RESOURCE_LEDGER.iter_mut() {
        entry.rate = 0.0;
    }

    // Sum active producers
    for producer in PRODUCERS.iter() {
        if producer.active {
            if let Some(mut entry) = RESOURCE_LEDGER.get_mut(&producer.resource_type) {
                entry.rate += producer.rate_per_sec;
            }
        }
    }

    // Subtract active consumers
    for consumer in CONSUMERS.iter() {
        if consumer.active {
            if let Some(mut entry) = RESOURCE_LEDGER.get_mut(&consumer.resource_type) {
                entry.rate -= consumer.rate_per_sec;
            }
        }
    }
}

/// Internal tick function (runs on worker thread)
/// Returns Vec<(ResourceType, current, cap)> for changed resources (to emit signals)
fn tick_internal(delta_s: f32) -> Vec<(ResourceType, f32, f32)> {
    let mut changed = Vec::new();

    // Recalculate rates based on active producers/consumers
    recalculate_rates();

    // Apply rates to all resources
    for mut entry in RESOURCE_LEDGER.iter_mut() {
        if entry.rate != 0.0 {
            let old_current = entry.current;
            entry.current = (entry.current + entry.rate * delta_s).clamp(0.0, entry.cap);

            // Track changes for signals
            if entry.current != old_current {
                changed.push((*entry.key(), entry.current, entry.cap));
            }
        }
    }

    changed
}

/// Request a tick (async - queues request for worker thread)
pub fn request_tick(delta_s: f32) {
    TICK_REQUESTS.push(TickRequest { delta_s });
}

/// Get tick result (non-blocking, called from main thread)
pub fn get_tick_result() -> Option<TickResult> {
    TICK_RESULTS.pop()
}

/// Get statistics for debugging
pub fn get_stats() -> String {
    let mut stats = String::from("=== Resource Ledger Stats ===\n");

    for entry in RESOURCE_LEDGER.iter() {
        stats.push_str(&format!(
            "{:?}: {:.1}/{:.1} (rate: {:.2}/s)\n",
            entry.key(), entry.current, entry.cap, entry.rate
        ));
    }

    stats.push_str(&format!("\nProducers: {}\n", PRODUCERS.len()));
    stats.push_str(&format!("Consumers: {}\n", CONSUMERS.len()));

    stats
}

/// Save to dictionary format
pub fn to_save_data() -> Vec<(i32, f32, f32)> {
    RESOURCE_LEDGER
        .iter()
        .map(|entry| (*entry.key() as i32, entry.current, entry.cap))
        .collect()
}

/// Load from save data
pub fn load_save_data(data: &[(i32, f32, f32)]) {
    for (type_id, current, cap) in data {
        if let Some(resource_type) = ResourceType::from_i32(*type_id) {
            if let Some(mut entry) = RESOURCE_LEDGER.get_mut(&resource_type) {
                entry.current = *current;
                entry.cap = *cap;
            }
        }
    }
}

/// Clear all producers and consumers (useful for testing/reset)
pub fn clear_producers_and_consumers() {
    PRODUCERS.clear();
    CONSUMERS.clear();
}
