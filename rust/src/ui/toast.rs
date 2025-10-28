use godot::prelude::*;
use crossbeam_queue::SegQueue;
use std::sync::Arc;
use std::thread;
use std::time::Duration;

/// Toast notification system for Rust threads -> Godot communication
///
/// This module provides a thread-safe way for any Rust worker thread to send
/// toast notifications to the Godot UI. Uses SegQueue for lock-free message passing.
///
/// Usage from Rust threads:
/// ```rust
/// use crate::ui::toast;
/// toast::send_message("Operation completed!".to_string());
/// ```

// Global message queue shared between Rust threads and GDScript
static MESSAGE_QUEUE: once_cell::sync::Lazy<Arc<SegQueue<String>>> =
    once_cell::sync::Lazy::new(|| Arc::new(SegQueue::new()));

/// Send a toast message from any Rust thread
/// This is the primary API that other Rust modules should use
pub fn send_message(message: String) {
    MESSAGE_QUEUE.push(message);
}

/// Send a formatted toast message
pub fn send_toast(format_args: std::fmt::Arguments) {
    MESSAGE_QUEUE.push(format!("{}", format_args));
}

/// Get current queue size (for debugging)
pub fn queue_size() -> usize {
    MESSAGE_QUEUE.len()
}

/// Clear all pending messages
pub fn clear_queue() {
    while MESSAGE_QUEUE.pop().is_some() {}
}

// GDScript bridge for toast notifications
#[derive(GodotClass)]
#[class(base=Node)]
pub struct ToastBridge {
    base: Base<Node>,
}

#[godot_api]
impl INode for ToastBridge {
    fn init(base: Base<Node>) -> Self {
        godot_print!("ToastBridge initialized!");
        Self { base }
    }

    fn ready(&mut self) {
        godot_print!("ToastBridge ready!");
        // Enable processing so process() gets called every frame
        self.base_mut().set_process(true);
    }

    fn process(&mut self, _delta: f64) {
        // Poll the message queue every frame
        while let Some(message) = MESSAGE_QUEUE.pop() {
            // Emit signal to GDScript with the message
            self.base_mut().emit_signal(
                "toast_message_received",
                &[message.to_variant()]
            );
        }
    }
}

#[godot_api]
impl ToastBridge {
    /// Signal that GDScript will connect to
    #[signal]
    fn toast_message_received(message: GString);

    /// Spawn a test thread that sends a toast message after 2 seconds
    #[func]
    fn spawn_test_thread(&mut self) {
        godot_print!("Spawning Rust test thread...");

        thread::Builder::new()
            .name("toast_test".to_string())
            .spawn(move || {
                godot_print!("Rust thread started! Sleeping for 2 seconds...");
                thread::sleep(Duration::from_secs(2));

                // Use the public API to send message
                send_message("Toast from Rust thread!".to_string());
                godot_print!("Rust thread: Message sent to queue!");
            })
            .expect("Failed to spawn test thread");
    }

    /// Spawn a thread that sends multiple messages
    #[func]
    fn spawn_multi_message_thread(&mut self, count: i32, delay_ms: i64) {
        godot_print!("Spawning multi-message Rust thread (count={}, delay={}ms)...", count, delay_ms);

        thread::spawn(move || {
            for i in 1..=count {
                thread::sleep(Duration::from_millis(delay_ms as u64));
                send_message(format!("Rust message #{}", i));
                godot_print!("Rust thread: Sent message #{}", i);
            }
            godot_print!("Rust thread: All messages sent!");
        });
    }

    /// Get the current queue size (for debugging)
    #[func]
    fn get_queue_size(&self) -> i32 {
        queue_size() as i32
    }

    /// Clear the message queue
    #[func]
    fn clear_queue(&mut self) {
        clear_queue();
        godot_print!("Message queue cleared!");
    }
}
