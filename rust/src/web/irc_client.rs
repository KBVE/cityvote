// IRC client implementation using WebSocket transport
// Handles Ergo WebIRC protocol flow and state management

use godot::prelude::*;
use super::irc::{IrcCommands, IrcConfig, IrcConnectionState, IrcEvent, IrcMessage};
use super::network_worker::{NetworkWorkerHandle, NetworkWorkerRequest, NetworkWorkerResponse};
use crossbeam_channel::{unbounded, Receiver, Sender};
use std::collections::VecDeque;

/// IRC client that manages WebSocket connection and IRC protocol
pub struct IrcClient {
    config: IrcConfig,
    state: IrcConnectionState,
    network_worker: NetworkWorkerHandle,
    event_tx: Sender<IrcEvent>,
    event_rx: Receiver<IrcEvent>,
    pending_messages: VecDeque<String>,
    current_channel: Option<String>,
}

impl IrcClient {
    /// Create a new IRC client
    pub fn new(config: IrcConfig, network_worker: NetworkWorkerHandle) -> Self {
        let (event_tx, event_rx) = unbounded();

        Self {
            config,
            state: IrcConnectionState::Disconnected,
            network_worker,
            event_tx,
            event_rx,
            pending_messages: VecDeque::new(),
            current_channel: None,
        }
    }

    /// Connect to IRC server
    pub fn connect(&mut self) {
        godot_print!("[IRC] IrcClient::connect() - setting state to Connecting");
        self.state = IrcConnectionState::Connecting;
        godot_print!("[IRC] IrcClient::connect() - calling network_worker.connect({})", self.config.url);
        self.network_worker.connect(self.config.url.clone());
        godot_print!("[IRC] IrcClient::connect() - network_worker.connect() returned");
    }

    /// Disconnect from IRC server
    pub fn disconnect(&mut self, message: Option<&str>) {
        self.state = IrcConnectionState::Disconnecting;

        // Send QUIT command
        let quit_msg = IrcCommands::quit(message);
        self.send_raw(&quit_msg.to_string());

        // Close WebSocket
        self.network_worker.disconnect();
    }

    /// Send a message to a channel or user
    pub fn send_message(&mut self, target: &str, message: &str) {
        let msg = IrcCommands::privmsg(target, message);
        self.send_raw(&msg.to_string());
    }

    /// Send a message to the current channel
    pub fn send_channel_message(&mut self, message: &str) {
        if let Some(channel) = self.current_channel.clone() {
            self.send_message(&channel, message);
        }
    }

    /// Join a channel
    pub fn join_channel(&mut self, channel: &str) {
        let msg = IrcCommands::join(channel);
        self.send_raw(&msg.to_string());
    }

    /// Leave a channel
    pub fn leave_channel(&mut self, channel: &str, message: Option<&str>) {
        let msg = IrcCommands::part(channel, message);
        self.send_raw(&msg.to_string());
    }

    /// Get current connection state
    pub fn state(&self) -> IrcConnectionState {
        self.state
    }

    /// Try to receive an IRC event (non-blocking)
    pub fn try_recv_event(&self) -> Option<IrcEvent> {
        self.event_rx.try_recv().ok()
    }

    /// Process network worker responses (call this regularly)
    pub fn process(&mut self) {
        // Process network worker responses
        static LOGGED_ONCE: std::sync::atomic::AtomicBool = std::sync::atomic::AtomicBool::new(false);
        if !LOGGED_ONCE.swap(true, std::sync::atomic::Ordering::Relaxed) {
            godot_print!("[IRC] IrcClient::process() called for the first time!");
        }

        while let Some(response) = self.network_worker.try_recv() {
            godot_print!("[IRC] IrcClient::process() received response: {:?}", response);
            match response {
                NetworkWorkerResponse::Connected => {
                    godot_print!("[IRC] IrcClient::process() calling handle_websocket_connected()");
                    self.handle_websocket_connected();
                }
                NetworkWorkerResponse::Disconnected => {
                    self.handle_websocket_disconnected(None);
                }
                NetworkWorkerResponse::MessageReceived { data } => {
                    if let Ok(text) = String::from_utf8(data) {
                        self.handle_websocket_message(&text);
                    }
                }
                NetworkWorkerResponse::TextReceived { text } => {
                    self.handle_websocket_message(&text);
                }
                NetworkWorkerResponse::ConnectionFailed { error } => {
                    self.handle_websocket_disconnected(Some(error));
                }
                NetworkWorkerResponse::Error { message } => {
                    let _ = self.event_tx.send(IrcEvent::Error { message });
                }
                _ => {}
            }
        }
    }

    // ========================================================================
    // PRIVATE METHODS
    // ========================================================================

    /// Send raw IRC message
    fn send_raw(&mut self, message: &str) {
        self.network_worker.send_text(message.to_string());
    }

    /// Handle WebSocket connected
    fn handle_websocket_connected(&mut self) {
        godot_print!("[IRC] WebSocket connected! Sending registration...");
        self.state = IrcConnectionState::Registering;

        // Send registration commands
        if let Some(ref password) = self.config.password {
            let pass_msg = IrcCommands::pass(password);
            godot_print!("[IRC] Sending PASS command");
            self.send_raw(&pass_msg.to_string());
        }

        let nick_msg = IrcCommands::nick(&self.config.nickname());
        godot_print!("[IRC] Sending NICK: {}", self.config.nickname());
        self.send_raw(&nick_msg.to_string());

        let user_msg = IrcCommands::user(&self.config.username, &self.config.realname);
        godot_print!("[IRC] Sending USER command");
        self.send_raw(&user_msg.to_string());
    }

    /// Handle WebSocket disconnected
    fn handle_websocket_disconnected(&mut self, reason: Option<String>) {
        godot_print!("[IRC] WebSocket disconnected: {:?}", reason);
        self.state = IrcConnectionState::Disconnected;
        self.current_channel = None;

        let _ = self.event_tx.send(IrcEvent::Disconnected { reason });
    }

    /// Handle WebSocket text message (IRC protocol)
    fn handle_websocket_message(&mut self, text: &str) {
        godot_print!("[IRC] Received: {}", text.trim());
        // IRC messages can be split across multiple lines
        self.pending_messages.push_back(text.to_string());

        // Process all complete messages
        while let Some(line) = self.get_next_line() {
            godot_print!("[IRC] Parsing line: {}", line.trim());
            if let Some(msg) = IrcMessage::parse(&line) {
                godot_print!("[IRC] Parsed command: {}", msg.command);
                self.handle_irc_message(msg);
            } else {
                godot_print!("[IRC] Failed to parse line: {}", line.trim());
            }
        }
    }

    /// Get next complete IRC message from buffer
    fn get_next_line(&mut self) -> Option<String> {
        if let Some(text) = self.pending_messages.front_mut() {
            if let Some(pos) = text.find('\n') {
                // Found a newline - extract up to and including it
                let line = text[..=pos].to_string();
                *text = text[pos + 1..].to_string();

                if text.is_empty() {
                    self.pending_messages.pop_front();
                }

                return Some(line);
            } else if !text.is_empty() {
                // No newline found, but we have text
                // WebSocket sends each IRC message as a separate frame without newlines
                // So treat the entire text as one complete message
                return self.pending_messages.pop_front();
            }
        }
        None
    }

    /// Handle parsed IRC message
    fn handle_irc_message(&mut self, msg: IrcMessage) {
        match msg.command.as_str() {
            // Server PING - respond with PONG
            "PING" => {
                if let Some(server) = msg.params.get(0) {
                    let pong = IrcCommands::pong(server);
                    self.send_raw(&pong.to_string());
                }
            }

            // Welcome message - we're registered!
            "001" => {
                godot_print!("[IRC] Received 001 welcome message - registration successful!");
                self.state = IrcConnectionState::Connected;

                let server = msg.prefix.unwrap_or_else(|| "server".to_string());
                let _ = self.event_tx.send(IrcEvent::Connected {
                    nickname: self.config.nickname(),
                    server,
                });

                // Auto-join channel if configured
                if let Some(channel) = self.config.channel.clone() {
                    godot_print!("[IRC] Auto-joining channel: {}", channel);
                    self.join_channel(&channel);
                } else {
                    godot_print!("[IRC] No channel configured for auto-join");
                }
            }

            // JOIN - someone (including us) joined a channel
            "JOIN" => {
                if let (Some(prefix), Some(channel)) = (&msg.prefix, msg.params.get(0)) {
                    let nickname = extract_nickname(prefix);
                    let channel = channel.trim_start_matches(':');

                    if nickname == self.config.nickname() {
                        godot_print!("[IRC] Successfully joined channel: {}", channel);
                        self.state = IrcConnectionState::Joined;
                        self.current_channel = Some(channel.to_string());
                    } else {
                        godot_print!("[IRC] User {} joined channel: {}", nickname, channel);
                    }

                    let _ = self.event_tx.send(IrcEvent::UserJoined {
                        channel: channel.to_string(),
                        nickname: nickname.to_string(),
                    });
                }
            }

            // PART - someone left a channel
            "PART" => {
                if let (Some(prefix), Some(channel)) = (&msg.prefix, msg.params.get(0)) {
                    let nickname = extract_nickname(prefix);
                    let message = msg.params.get(1).map(|s| s.trim_start_matches(':').to_string());

                    if nickname == self.config.nickname() {
                        if Some(channel.as_str()) == self.current_channel.as_deref() {
                            self.current_channel = None;
                        }
                    }

                    let _ = self.event_tx.send(IrcEvent::UserParted {
                        channel: channel.to_string(),
                        nickname: nickname.to_string(),
                        message,
                    });
                }
            }

            // QUIT - someone quit IRC
            "QUIT" => {
                if let Some(prefix) = &msg.prefix {
                    let nickname = extract_nickname(prefix);
                    let message = msg.params.get(0).map(|s| s.trim_start_matches(':').to_string());

                    let _ = self.event_tx.send(IrcEvent::UserQuit {
                        nickname: nickname.to_string(),
                        message,
                    });
                }
            }

            // NICK - someone changed nickname
            "NICK" => {
                if let (Some(prefix), Some(new_nick)) = (&msg.prefix, msg.params.get(0)) {
                    let old_nick = extract_nickname(prefix);
                    let new_nick = new_nick.trim_start_matches(':');

                    let _ = self.event_tx.send(IrcEvent::NickChanged {
                        old_nick: old_nick.to_string(),
                        new_nick: new_nick.to_string(),
                    });
                }
            }

            // PRIVMSG - channel or private message
            "PRIVMSG" => {
                if let (Some(prefix), Some(target), Some(text)) =
                    (&msg.prefix, msg.params.get(0), msg.params.get(1))
                {
                    let sender = extract_nickname(prefix);
                    let message = text.trim_start_matches(':').to_string();

                    if target.starts_with('#') {
                        // Channel message
                        let _ = self.event_tx.send(IrcEvent::ChannelMessage {
                            channel: target.to_string(),
                            sender: sender.to_string(),
                            message,
                        });
                    } else {
                        // Private message
                        let _ = self.event_tx.send(IrcEvent::PrivateMessage {
                            sender: sender.to_string(),
                            message,
                        });
                    }
                }
            }

            // NOTICE - server or user notice
            "NOTICE" => {
                if let Some(text) = msg.params.get(1) {
                    let sender = msg.prefix.as_ref().map(|p| extract_nickname(p).to_string());
                    let message = text.trim_start_matches(':').to_string();

                    let _ = self.event_tx.send(IrcEvent::Notice { sender, message });
                }
            }

            // Error messages
            cmd if cmd.starts_with('4') || cmd.starts_with('5') => {
                let error_msg = msg
                    .params
                    .last()
                    .map(|s| s.trim_start_matches(':').to_string())
                    .unwrap_or_else(|| format!("IRC Error: {}", cmd));

                let _ = self.event_tx.send(IrcEvent::Error { message: error_msg });
            }

            _ => {
                // Unhandled command - could log for debugging
            }
        }
    }
}

/// Extract nickname from IRC prefix (nick!user@host -> nick)
fn extract_nickname(prefix: &str) -> &str {
    prefix.split('!').next().unwrap_or(prefix)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_extract_nickname() {
        assert_eq!(extract_nickname("alice!user@host"), "alice");
        assert_eq!(extract_nickname("bob"), "bob");
        assert_eq!(extract_nickname("charlie!~user@192.168.1.1"), "charlie");
    }
}
