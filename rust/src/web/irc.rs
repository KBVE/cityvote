// IRC protocol implementation for Ergo WebIRC
// Handles IRC message parsing, building, and protocol flow

use serde::{Deserialize, Serialize};

/// IRC message structure
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct IrcMessage {
    pub prefix: Option<String>,
    pub command: String,
    pub params: Vec<String>,
}

impl IrcMessage {
    /// Create a new IRC message
    pub fn new(command: impl Into<String>) -> Self {
        Self {
            prefix: None,
            command: command.into(),
            params: Vec::new(),
        }
    }

    /// Add a parameter to the message
    pub fn param(mut self, param: impl Into<String>) -> Self {
        self.params.push(param.into());
        self
    }

    /// Add a trailing parameter (prefixed with ':')
    pub fn trailing(mut self, text: impl Into<String>) -> Self {
        let text = text.into();
        // IRC protocol: trailing params start with ':'
        if !text.is_empty() {
            self.params.push(format!(":{}", text));
        }
        self
    }

    /// Serialize to IRC protocol string
    pub fn to_string(&self) -> String {
        let mut result = String::new();

        if let Some(ref prefix) = self.prefix {
            result.push(':');
            result.push_str(prefix);
            result.push(' ');
        }

        result.push_str(&self.command);

        for param in &self.params {
            result.push(' ');
            result.push_str(param);
        }

        result.push_str("\r\n");
        result
    }

    /// Parse IRC message from string
    pub fn parse(line: &str) -> Option<Self> {
        let line = line.trim_end_matches("\r\n").trim_end_matches('\n');
        if line.is_empty() {
            return None;
        }

        let mut parts = line.split(' ').peekable();
        let mut prefix = None;

        // Check for prefix
        let first = parts.peek()?;
        if first.starts_with(':') {
            prefix = Some(parts.next()?.trim_start_matches(':').to_string());
        }

        // Get command
        let command = parts.next()?.to_string();

        // Get params
        let mut params: Vec<String> = Vec::new();
        let mut trailing_started = false;

        for part in parts {
            if trailing_started {
                // Continue building trailing param
                if let Some(last) = params.last_mut() {
                    last.push(' ');
                    last.push_str(part);
                }
            } else if part.starts_with(':') {
                // Start of trailing param
                trailing_started = true;
                params.push(part.to_string());
            } else {
                params.push(part.to_string());
            }
        }

        Some(Self {
            prefix,
            command,
            params,
        })
    }
}

/// IRC connection state
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum IrcConnectionState {
    Disconnected,
    Connecting,
    Registering,      // Sent NICK/USER, waiting for welcome
    Connected,        // Received 001 (RPL_WELCOME)
    Joined,           // Joined a channel
    Disconnecting,
}

/// IRC client configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IrcConfig {
    /// WebSocket URL (e.g., "wss://chat.kbve.com/webirc")
    pub url: String,

    /// Nickname (will be prefixed with "CityVote_")
    pub player_name: String,

    /// Username (ident)
    pub username: String,

    /// Real name
    pub realname: String,

    /// Channel to auto-join (e.g., "#cityvote")
    pub channel: Option<String>,

    /// Server password (if required)
    pub password: Option<String>,
}

impl IrcConfig {
    /// Create config for CityVote IRC
    pub fn cityvote(player_name: impl Into<String>) -> Self {
        let player_name = player_name.into();
        let nickname = format!("CityVote_{}", player_name);

        Self {
            url: "wss://chat.kbve.com/webirc".to_string(),
            player_name: player_name.clone(),
            username: nickname.clone(),
            realname: format!("CityVote Player: {}", player_name),
            channel: Some("#general".to_string()),  // Changed from #cityvote to #general
            password: None,
        }
    }

    /// Get the full nickname with prefix
    pub fn nickname(&self) -> String {
        format!("CityVote_{}", self.player_name)
    }
}

/// IRC events that can be emitted to the game
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum IrcEvent {
    /// Connected and registered with IRC server
    Connected {
        nickname: String,
        server: String,
    },

    /// Disconnected from IRC server
    Disconnected {
        reason: Option<String>,
    },

    /// Joined a channel
    Joined {
        channel: String,
        nickname: String,
    },

    /// Left a channel
    Parted {
        channel: String,
        nickname: String,
        message: Option<String>,
    },

    /// Received a message in a channel
    ChannelMessage {
        channel: String,
        sender: String,
        message: String,
    },

    /// Received a private message
    PrivateMessage {
        sender: String,
        message: String,
    },

    /// Server NOTICE
    Notice {
        sender: Option<String>,
        message: String,
    },

    /// User joined a channel
    UserJoined {
        channel: String,
        nickname: String,
    },

    /// User left a channel
    UserParted {
        channel: String,
        nickname: String,
        message: Option<String>,
    },

    /// User quit IRC
    UserQuit {
        nickname: String,
        message: Option<String>,
    },

    /// Nick changed
    NickChanged {
        old_nick: String,
        new_nick: String,
    },

    /// IRC error
    Error {
        message: String,
    },
}

/// IRC command builder helpers
pub struct IrcCommands;

impl IrcCommands {
    /// Create NICK command
    pub fn nick(nickname: &str) -> IrcMessage {
        IrcMessage::new("NICK").param(nickname)
    }

    /// Create USER command
    pub fn user(username: &str, realname: &str) -> IrcMessage {
        IrcMessage::new("USER")
            .param(username)
            .param("0")
            .param("*")
            .trailing(realname)
    }

    /// Create PASS command (for server password)
    pub fn pass(password: &str) -> IrcMessage {
        IrcMessage::new("PASS").param(password)
    }

    /// Create JOIN command
    pub fn join(channel: &str) -> IrcMessage {
        IrcMessage::new("JOIN").param(channel)
    }

    /// Create PART command
    pub fn part(channel: &str, message: Option<&str>) -> IrcMessage {
        let mut msg = IrcMessage::new("PART").param(channel);
        if let Some(text) = message {
            msg = msg.trailing(text);
        }
        msg
    }

    /// Create PRIVMSG command
    pub fn privmsg(target: &str, message: &str) -> IrcMessage {
        IrcMessage::new("PRIVMSG")
            .param(target)
            .trailing(message)
    }

    /// Create QUIT command
    pub fn quit(message: Option<&str>) -> IrcMessage {
        let mut msg = IrcMessage::new("QUIT");
        if let Some(text) = message {
            msg = msg.trailing(text);
        }
        msg
    }

    /// Create PONG command (response to PING)
    pub fn pong(server: &str) -> IrcMessage {
        IrcMessage::new("PONG").param(server)
    }

    /// Create PING command
    pub fn ping(server: &str) -> IrcMessage {
        IrcMessage::new("PING").param(server)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_irc_message_to_string() {
        let msg = IrcMessage::new("PRIVMSG")
            .param("#cityvote")
            .trailing("Hello, world!");

        assert_eq!(msg.to_string(), "PRIVMSG #cityvote :Hello, world!\r\n");
    }

    #[test]
    fn test_irc_message_parse() {
        let msg = IrcMessage::parse("PRIVMSG #cityvote :Hello, world!").unwrap();
        assert_eq!(msg.command, "PRIVMSG");
        assert_eq!(msg.params[0], "#cityvote");
        assert_eq!(msg.params[1], ":Hello, world!");
    }

    #[test]
    fn test_irc_message_parse_with_prefix() {
        let msg = IrcMessage::parse(":nick!user@host PRIVMSG #cityvote :Test").unwrap();
        assert_eq!(msg.prefix, Some("nick!user@host".to_string()));
        assert_eq!(msg.command, "PRIVMSG");
    }

    #[test]
    fn test_nick_command() {
        let msg = IrcCommands::nick("TestUser");
        assert_eq!(msg.to_string(), "NICK TestUser\r\n");
    }

    #[test]
    fn test_user_command() {
        let msg = IrcCommands::user("testuser", "Test User");
        assert_eq!(msg.to_string(), "USER testuser 0 * :Test User\r\n");
    }

    #[test]
    fn test_privmsg_command() {
        let msg = IrcCommands::privmsg("#test", "Hello!");
        assert_eq!(msg.to_string(), "PRIVMSG #test :Hello!\r\n");
    }

    #[test]
    fn test_cityvote_config() {
        let config = IrcConfig::cityvote("Alice");
        assert_eq!(config.nickname(), "CityVote_Alice");
        assert_eq!(config.username, "CityVote_Alice");
        assert_eq!(config.url, "wss://chat.kbve.com/webirc");
        assert_eq!(config.channel, Some("#cityvote".to_string()));
    }

    #[test]
    fn test_parse_001_welcome() {
        // Test parsing the actual 001 message from the logs
        let line = ":irc.kbve.com 001 CityVote_Player :Welcome to the KBVE-Network IRC Network CityVote_Player";
        let msg = IrcMessage::parse(line).unwrap();

        assert_eq!(msg.prefix, Some("irc.kbve.com".to_string()));
        assert_eq!(msg.command, "001");
        assert_eq!(msg.params.len(), 2);
        assert_eq!(msg.params[0], "CityVote_Player");
        assert_eq!(msg.params[1], ":Welcome to the KBVE-Network IRC Network CityVote_Player");
    }

    #[test]
    fn test_parse_001_with_newline() {
        // Test with newline characters as they come from WebSocket
        let line = ":irc.kbve.com 001 CityVote_Player :Welcome to the KBVE-Network IRC Network CityVote_Player\r\n";
        let msg = IrcMessage::parse(line).unwrap();

        assert_eq!(msg.command, "001");
        assert_eq!(msg.params.len(), 2);
    }
}
