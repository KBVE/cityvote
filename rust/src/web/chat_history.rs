// Chat history storage for IRC messages
// Stores messages in a ring buffer per channel

use serde::{Deserialize, Serialize};
use std::collections::VecDeque;

/// Single chat message
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatMessage {
    /// Sender nickname
    pub sender: String,

    /// Message text
    pub message: String,

    /// Unix timestamp (seconds since epoch)
    pub timestamp: u64,

    /// Message type
    pub msg_type: MessageType,
}

/// Message type classification
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum MessageType {
    /// Regular channel message
    Channel,

    /// Private message
    Private,

    /// System message (join/part/quit)
    System,

    /// Error message
    Error,
}

impl ChatMessage {
    /// Create a new chat message
    pub fn new(sender: impl Into<String>, message: impl Into<String>, msg_type: MessageType) -> Self {
        Self {
            sender: sender.into(),
            message: message.into(),
            timestamp: current_timestamp(),
            msg_type,
        }
    }

    /// Create a channel message
    pub fn channel(sender: impl Into<String>, message: impl Into<String>) -> Self {
        Self::new(sender, message, MessageType::Channel)
    }

    /// Create a private message
    pub fn private(sender: impl Into<String>, message: impl Into<String>) -> Self {
        Self::new(sender, message, MessageType::Private)
    }

    /// Create a system message
    pub fn system(message: impl Into<String>) -> Self {
        Self::new("*", message, MessageType::System)
    }

    /// Create an error message
    pub fn error(message: impl Into<String>) -> Self {
        Self::new("!", message, MessageType::Error)
    }
}

/// Chat history for a single channel
#[derive(Debug, Clone)]
pub struct ChannelHistory {
    /// Channel name (e.g., "#cityvote")
    pub channel: String,

    /// Ring buffer of messages (newest at back)
    messages: VecDeque<ChatMessage>,

    /// Maximum messages to store
    max_messages: usize,
}

impl ChannelHistory {
    /// Create a new channel history
    pub fn new(channel: impl Into<String>, max_messages: usize) -> Self {
        Self {
            channel: channel.into(),
            messages: VecDeque::with_capacity(max_messages),
            max_messages,
        }
    }

    /// Add a message to history
    pub fn add_message(&mut self, message: ChatMessage) {
        if self.messages.len() >= self.max_messages {
            self.messages.pop_front(); // Remove oldest
        }
        self.messages.push_back(message);
    }

    /// Get all messages
    pub fn messages(&self) -> &VecDeque<ChatMessage> {
        &self.messages
    }

    /// Get last N messages
    pub fn last_n(&self, n: usize) -> Vec<ChatMessage> {
        let start = self.messages.len().saturating_sub(n);
        self.messages.range(start..).cloned().collect()
    }

    /// Get messages after a timestamp
    pub fn messages_after(&self, timestamp: u64) -> Vec<ChatMessage> {
        self.messages
            .iter()
            .filter(|msg| msg.timestamp > timestamp)
            .cloned()
            .collect()
    }

    /// Search messages by text
    pub fn search(&self, query: &str) -> Vec<ChatMessage> {
        let query_lower = query.to_lowercase();
        self.messages
            .iter()
            .filter(|msg| {
                msg.message.to_lowercase().contains(&query_lower)
                    || msg.sender.to_lowercase().contains(&query_lower)
            })
            .cloned()
            .collect()
    }

    /// Filter messages by sender
    pub fn from_sender(&self, sender: &str) -> Vec<ChatMessage> {
        self.messages
            .iter()
            .filter(|msg| msg.sender.eq_ignore_ascii_case(sender))
            .cloned()
            .collect()
    }

    /// Clear all messages
    pub fn clear(&mut self) {
        self.messages.clear();
    }

    /// Get message count
    pub fn len(&self) -> usize {
        self.messages.len()
    }

    /// Check if empty
    pub fn is_empty(&self) -> bool {
        self.messages.is_empty()
    }
}

/// Get current Unix timestamp
fn current_timestamp() -> u64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_channel_history() {
        let mut history = ChannelHistory::new("#test", 10);

        history.add_message(ChatMessage::channel("alice", "Hello!"));
        history.add_message(ChatMessage::channel("bob", "Hi there!"));
        history.add_message(ChatMessage::system("alice joined the channel"));

        assert_eq!(history.len(), 3);
        assert_eq!(history.messages()[0].sender, "alice");
        assert_eq!(history.messages()[1].sender, "bob");
    }

    #[test]
    fn test_ring_buffer() {
        let mut history = ChannelHistory::new("#test", 3);

        history.add_message(ChatMessage::channel("user1", "msg1"));
        history.add_message(ChatMessage::channel("user2", "msg2"));
        history.add_message(ChatMessage::channel("user3", "msg3"));
        history.add_message(ChatMessage::channel("user4", "msg4")); // Should push out msg1

        assert_eq!(history.len(), 3);
        assert_eq!(history.messages()[0].sender, "user2");
        assert_eq!(history.messages()[2].sender, "user4");
    }

    #[test]
    fn test_search() {
        let mut history = ChannelHistory::new("#test", 10);

        history.add_message(ChatMessage::channel("alice", "Hello world!"));
        history.add_message(ChatMessage::channel("bob", "Goodbye!"));
        history.add_message(ChatMessage::channel("alice", "Hello again!"));

        let results = history.search("hello");
        assert_eq!(results.len(), 2);

        let from_alice = history.from_sender("alice");
        assert_eq!(from_alice.len(), 2);
    }
}
