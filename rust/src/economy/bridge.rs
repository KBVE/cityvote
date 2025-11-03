use godot::prelude::*;
use godot::classes::{Node, INode};
use super::resource_ledger;

/// Godot-Rust bridge for ResourceLedger
/// Connects to GameTimer signals and emits resource changes back to GDScript
#[derive(GodotClass)]
#[class(base=Node)]
pub struct ResourceLedgerBridge {
    #[base]
    base: Base<Node>,
}

#[godot_api]
impl INode for ResourceLedgerBridge {
    fn init(base: Base<Node>) -> Self {
        // Initialize Rust ledger (starts worker thread)
        resource_ledger::initialize();

        Self { base }
    }

    fn ready(&mut self) {
        // Ready - worker thread started
    }

    fn process(&mut self, _delta: f64) {
        // Check for tick results from worker thread and emit signals
        while let Some(result) = resource_ledger::get_tick_result() {
            for (resource_type, current, cap) in result.changes {
                let rate = resource_ledger::get_rate(resource_type);
                self.base_mut().emit_signal(
                    "resource_changed",
                    &[
                        (resource_type as i32).to_variant(),
                        current.to_variant(),
                        cap.to_variant(),
                        rate.to_variant(),
                    ],
                );
            }
        }
    }
}

#[godot_api]
impl ResourceLedgerBridge {
    /// Signal emitted when a resource changes
    /// Args: resource_type (int), current (float), cap (float), rate (float)
    #[signal]
    fn resource_changed(resource_type: i32, current: f32, cap: f32, rate: f32);

    /// Called by GameTimer every second (via signal connection)
    /// Queues a tick request for the worker thread (non-blocking)
    #[func]
    fn on_timer_tick(&mut self, _time_left: i32) {
        // Queue tick request for worker thread (1 second delta)
        resource_ledger::request_tick(1.0);
        // Results will be processed in process() and signals emitted there
    }

    /// Get current amount of a resource
    #[func]
    fn get_current(&self, resource_type: i32) -> f32 {
        if let Some(rt) = resource_ledger::ResourceType::from_i32(resource_type) {
            resource_ledger::get_current(rt)
        } else {
            0.0
        }
    }

    /// Get cap of a resource
    #[func]
    fn get_cap(&self, resource_type: i32) -> f32 {
        if let Some(rt) = resource_ledger::ResourceType::from_i32(resource_type) {
            resource_ledger::get_cap(rt)
        } else {
            0.0
        }
    }

    /// Get net rate of a resource
    #[func]
    fn get_rate(&self, resource_type: i32) -> f32 {
        if let Some(rt) = resource_ledger::ResourceType::from_i32(resource_type) {
            resource_ledger::get_rate(rt)
        } else {
            0.0
        }
    }

    /// Set the cap for a resource
    #[func]
    fn set_cap(&mut self, resource_type: i32, cap: f32) {
        if let Some(rt) = resource_ledger::ResourceType::from_i32(resource_type) {
            resource_ledger::set_cap(rt, cap);

            // Emit change signal
            let current = resource_ledger::get_current(rt);
            let rate = resource_ledger::get_rate(rt);
            self.base_mut().emit_signal(
                "resource_changed",
                &[resource_type.to_variant(), current.to_variant(), cap.to_variant(), rate.to_variant()],
            );
        }
    }

    /// Set current amount (clamped to [0, cap])
    #[func]
    fn set_current(&mut self, resource_type: i32, amount: f32) {
        if let Some(rt) = resource_ledger::ResourceType::from_i32(resource_type) {
            resource_ledger::set_current(rt, amount);

            // Emit change signal
            let current = resource_ledger::get_current(rt);
            let cap = resource_ledger::get_cap(rt);
            let rate = resource_ledger::get_rate(rt);
            self.base_mut().emit_signal(
                "resource_changed",
                &[resource_type.to_variant(), current.to_variant(), cap.to_variant(), rate.to_variant()],
            );
        }
    }

    /// Add to current amount (clamped to [0, cap])
    #[func]
    fn add(&mut self, resource_type: i32, amount: f32) {
        if let Some(rt) = resource_ledger::ResourceType::from_i32(resource_type) {
            resource_ledger::add(rt, amount);

            // Emit change signal
            let current = resource_ledger::get_current(rt);
            let cap = resource_ledger::get_cap(rt);
            let rate = resource_ledger::get_rate(rt);
            self.base_mut().emit_signal(
                "resource_changed",
                &[resource_type.to_variant(), current.to_variant(), cap.to_variant(), rate.to_variant()],
            );
        }
    }

    /// Check if we can spend resources
    /// cost_dict: Dictionary of {resource_type: int -> amount: float}
    #[func]
    fn can_spend(&self, cost_dict: Dictionary) -> bool {
        let cost: Vec<(resource_ledger::ResourceType, f32)> = cost_dict
            .iter_shared()
            .filter_map(|(k, v)| {
                let resource_type = k.try_to::<i32>().ok()?;
                let amount = v.try_to::<f32>().ok()?;
                let rt = resource_ledger::ResourceType::from_i32(resource_type)?;
                Some((rt, amount))
            })
            .collect();

        resource_ledger::can_spend(&cost)
    }

    /// Spend resources (returns false if not enough)
    /// cost_dict: Dictionary of {resource_type: int -> amount: float}
    #[func]
    fn spend(&mut self, cost_dict: Dictionary) -> bool {
        let cost: Vec<(resource_ledger::ResourceType, f32)> = cost_dict
            .iter_shared()
            .filter_map(|(k, v)| {
                let resource_type = k.try_to::<i32>().ok()?;
                let amount = v.try_to::<f32>().ok()?;
                let rt = resource_ledger::ResourceType::from_i32(resource_type)?;
                Some((rt, amount))
            })
            .collect();

        let success = resource_ledger::spend(&cost);

        if success {
            // Emit change signals for all spent resources
            for (rt, _) in cost {
                let current = resource_ledger::get_current(rt);
                let cap = resource_ledger::get_cap(rt);
                let rate = resource_ledger::get_rate(rt);
                self.base_mut().emit_signal(
                    "resource_changed",
                    &[(rt as i32).to_variant(), current.to_variant(), cap.to_variant(), rate.to_variant()],
                );
            }
        }

        success
    }

    /// Register a producer
    #[func]
    fn register_producer(&mut self, ulid: PackedByteArray, resource_type: i32, rate_per_sec: f32, active: bool) {
        if let Some(rt) = resource_ledger::ResourceType::from_i32(resource_type) {
            let ulid_bytes: Vec<u8> = ulid.to_vec();
            resource_ledger::register_producer(ulid_bytes, rt, rate_per_sec, active);
        }
    }

    /// Register a consumer
    #[func]
    fn register_consumer(&mut self, ulid: PackedByteArray, resource_type: i32, rate_per_sec: f32, active: bool) {
        if let Some(rt) = resource_ledger::ResourceType::from_i32(resource_type) {
            let ulid_bytes: Vec<u8> = ulid.to_vec();
            resource_ledger::register_consumer(ulid_bytes, rt, rate_per_sec, active);
        }
    }

    /// Set producer active state
    #[func]
    fn set_producer_active(&mut self, ulid: PackedByteArray, active: bool) {
        let ulid_bytes: Vec<u8> = ulid.to_vec();
        resource_ledger::set_producer_active(&ulid_bytes, active);
    }

    /// Set consumer active state
    #[func]
    fn set_consumer_active(&mut self, ulid: PackedByteArray, active: bool) {
        let ulid_bytes: Vec<u8> = ulid.to_vec();
        resource_ledger::set_consumer_active(&ulid_bytes, active);
    }

    /// Remove a producer
    #[func]
    fn remove_producer(&mut self, ulid: PackedByteArray) {
        let ulid_bytes: Vec<u8> = ulid.to_vec();
        resource_ledger::remove_producer(&ulid_bytes);
    }

    /// Remove a consumer
    #[func]
    fn remove_consumer(&mut self, ulid: PackedByteArray) {
        let ulid_bytes: Vec<u8> = ulid.to_vec();
        resource_ledger::remove_consumer(&ulid_bytes);
    }

    /// Print statistics (debugging)
    #[func]
    fn print_stats(&self) {
        let stats = resource_ledger::get_stats();
        godot_print!("{}", stats);
    }

    /// Get save data as Array of Dictionaries
    #[func]
    fn get_save_data(&self) -> Array<Dictionary> {
        let data = resource_ledger::to_save_data();
        let mut arr = Array::new();

        for (resource_type, current, cap) in data {
            let mut dict = Dictionary::new();
            dict.set("type", resource_type);
            dict.set("current", current);
            dict.set("cap", cap);
            arr.push(&dict);
        }

        arr
    }

    /// Load from save data (Array of Dictionaries)
    #[func]
    fn load_save_data(&mut self, data_array: Array<Dictionary>) {
        let data: Vec<(i32, f32, f32)> = data_array
            .iter_shared()
            .filter_map(|dict| {
                let resource_type = dict.get("type")?.try_to::<i32>().ok()?;
                let current = dict.get("current")?.try_to::<f32>().ok()?;
                let cap = dict.get("cap")?.try_to::<f32>().ok()?;
                Some((resource_type, current, cap))
            })
            .collect();

        resource_ledger::load_save_data(&data);

        // Emit signals for all loaded resources
        for (resource_type, current, cap) in data {
            if let Some(rt) = resource_ledger::ResourceType::from_i32(resource_type) {
                let rate = resource_ledger::get_rate(rt);
                self.base_mut().emit_signal(
                    "resource_changed",
                    &[resource_type.to_variant(), current.to_variant(), cap.to_variant(), rate.to_variant()],
                );
            }
        }
    }
}
