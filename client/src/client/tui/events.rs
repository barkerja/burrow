use chrono::{DateTime, Local};

use crate::protocol::RequestId;

/// Events that flow from the connection to the TUI
#[derive(Debug, Clone)]
pub enum TuiEvent {
    /// Tunnel successfully registered
    TunnelRegistered(TunnelEvent),
    /// TCP tunnel registered
    TcpTunnelRegistered(TcpTunnelEvent),
    /// Incoming HTTP request
    RequestReceived(RequestEvent),
    /// Response sent back
    ResponseSent(ResponseEvent),
    /// Connection status changed
    ConnectionStatus(ConnectionStatus),
}

/// Commands that flow from the TUI to the connection
#[derive(Debug, Clone)]
pub enum TuiCommand {
    /// Register a new HTTP tunnel
    AddHttpTunnel {
        local_port: u16,
        subdomain: Option<String>,
    },
    /// Register a new TCP tunnel
    AddTcpTunnel { local_port: u16 },
}

#[derive(Debug, Clone)]
pub struct TunnelEvent {
    pub full_url: String,
    pub local_port: u16,
}

#[derive(Debug, Clone)]
pub struct TcpTunnelEvent {
    pub server_port: u16,
    pub local_port: u16,
}

#[derive(Debug, Clone)]
pub struct RequestEvent {
    pub request_id: RequestId,
    pub method: String,
    pub path: String,
    pub query_string: String,
    pub headers: Vec<(String, String)>,
    pub body: Option<Vec<u8>>,
    pub timestamp: DateTime<Local>,
    pub client_ip: Option<String>,
}

#[derive(Debug, Clone)]
pub struct ResponseEvent {
    pub request_id: RequestId,
    pub status: u16,
    pub headers: Vec<(String, String)>,
    pub body: Option<Vec<u8>>,
    pub duration_ms: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ConnectionStatus {
    Connecting,
    Connected,
    Reconnecting {
        attempt: u32,
        reason: String,
        next_retry_secs: u64,
    },
    Disconnected {
        reason: String,
    },
}

impl std::fmt::Display for ConnectionStatus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ConnectionStatus::Connecting => write!(f, "Connecting"),
            ConnectionStatus::Connected => write!(f, "Connected"),
            ConnectionStatus::Reconnecting { attempt, .. } => {
                write!(f, "Reconnecting ({})", attempt)
            }
            ConnectionStatus::Disconnected { .. } => write!(f, "Disconnected"),
        }
    }
}
