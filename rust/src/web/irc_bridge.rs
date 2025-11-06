// GDScript FFI bridge for IRC chat history access
// Provides methods to query chat messages from GDScript

use godot::prelude::*;
use crate::events::actor::IRC_CHAT_HISTORY;

/// IRC Chat Bridge - GDScript interface for accessing chat history
#[derive(GodotClass)]
#[class(base=Node)]
pub struct IrcChatBridge {
    base: Base<Node>,
}

#[godot_api]
impl INode for IrcChatBridge {
    fn init(base: Base<Node>) -> Self {
        Self { base }
    }
}

#[godot_api]
impl IrcChatBridge {
    /// Get all messages from a channel
    /// Returns: Array of Dictionaries with keys: sender, message, timestamp, msg_type
    #[func]
    pub fn get_channel_messages(&self, channel: GString) -> Array<Dictionary> {
        let channel_str = channel.to_string();
        let mut result = Array::new();

        if let Some(history) = IRC_CHAT_HISTORY.get(&channel_str) {
            for msg in history.messages() {
                let mut dict = Dictionary::new();
                dict.set("sender", GString::from(&msg.sender));
                dict.set("message", GString::from(&msg.message));
                dict.set("timestamp", msg.timestamp as i64);
                dict.set("msg_type", msg.msg_type as i64);
                result.push(&dict);
            }
        }

        result
    }

    /// Get last N messages from a channel
    #[func]
    pub fn get_last_messages(&self, channel: GString, count: i64) -> Array<Dictionary> {
        let channel_str = channel.to_string();
        let mut result = Array::new();

        if let Some(history) = IRC_CHAT_HISTORY.get(&channel_str) {
            let messages = history.last_n(count as usize);
            for msg in messages {
                let mut dict = Dictionary::new();
                dict.set("sender", GString::from(&msg.sender));
                dict.set("message", GString::from(&msg.message));
                dict.set("timestamp", msg.timestamp as i64);
                dict.set("msg_type", msg.msg_type as i64);
                result.push(&dict);
            }
        }

        result
    }

    /// Get messages after a specific timestamp
    #[func]
    pub fn get_messages_after(&self, channel: GString, timestamp: i64) -> Array<Dictionary> {
        let channel_str = channel.to_string();
        let mut result = Array::new();

        if let Some(history) = IRC_CHAT_HISTORY.get(&channel_str) {
            let messages = history.messages_after(timestamp as u64);
            for msg in messages {
                let mut dict = Dictionary::new();
                dict.set("sender", GString::from(&msg.sender));
                dict.set("message", GString::from(&msg.message));
                dict.set("timestamp", msg.timestamp as i64);
                dict.set("msg_type", msg.msg_type as i64);
                result.push(&dict);
            }
        }

        result
    }

    /// Search messages in a channel
    #[func]
    pub fn search_messages(&self, channel: GString, query: GString) -> Array<Dictionary> {
        let channel_str = channel.to_string();
        let query_str = query.to_string();
        let mut result = Array::new();

        if let Some(history) = IRC_CHAT_HISTORY.get(&channel_str) {
            let messages = history.search(&query_str);
            for msg in messages {
                let mut dict = Dictionary::new();
                dict.set("sender", GString::from(&msg.sender));
                dict.set("message", GString::from(&msg.message));
                dict.set("timestamp", msg.timestamp as i64);
                dict.set("msg_type", msg.msg_type as i64);
                result.push(&dict);
            }
        }

        result
    }

    /// Get messages from a specific sender
    #[func]
    pub fn get_messages_from(&self, channel: GString, sender: GString) -> Array<Dictionary> {
        let channel_str = channel.to_string();
        let sender_str = sender.to_string();
        let mut result = Array::new();

        if let Some(history) = IRC_CHAT_HISTORY.get(&channel_str) {
            let messages = history.from_sender(&sender_str);
            for msg in messages {
                let mut dict = Dictionary::new();
                dict.set("sender", GString::from(&msg.sender));
                dict.set("message", GString::from(&msg.message));
                dict.set("timestamp", msg.timestamp as i64);
                dict.set("msg_type", msg.msg_type as i64);
                result.push(&dict);
            }
        }

        result
    }

    /// Get number of messages in a channel
    #[func]
    pub fn get_message_count(&self, channel: GString) -> i64 {
        let channel_str = channel.to_string();

        if let Some(history) = IRC_CHAT_HISTORY.get(&channel_str) {
            history.len() as i64
        } else {
            0
        }
    }

    /// Get list of all channels with messages
    #[func]
    pub fn get_channels(&self) -> Array<GString> {
        let mut result = Array::new();

        for entry in IRC_CHAT_HISTORY.iter() {
            let channel_name = GString::from(entry.key());
            result.push(&channel_name);
        }

        result
    }

    /// Clear all messages in a channel
    #[func]
    pub fn clear_channel(&self, channel: GString) {
        let channel_str = channel.to_string();

        if let Some(mut history) = IRC_CHAT_HISTORY.get_mut(&channel_str) {
            history.clear();
        }
    }
}
