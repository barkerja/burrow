//! Type-safe ID wrappers for protocol identifiers.
//!
//! These newtypes prevent accidentally mixing up different ID types
//! at compile time (e.g., passing a TunnelId where a RequestId is expected).

use serde::{Deserialize, Serialize};
use std::fmt;

/// Unique identifier for an HTTP tunnel
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(transparent)]
pub struct TunnelId(pub String);

impl fmt::Display for TunnelId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0)
    }
}

impl From<String> for TunnelId {
    fn from(s: String) -> Self {
        TunnelId(s)
    }
}

/// Unique identifier for an HTTP request
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(transparent)]
pub struct RequestId(pub String);

impl fmt::Display for RequestId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0)
    }
}

impl From<String> for RequestId {
    fn from(s: String) -> Self {
        RequestId(s)
    }
}

/// Unique identifier for a WebSocket connection
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(transparent)]
pub struct WsId(pub String);

impl fmt::Display for WsId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0)
    }
}

impl From<String> for WsId {
    fn from(s: String) -> Self {
        WsId(s)
    }
}

/// Unique identifier for a TCP tunnel
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(transparent)]
pub struct TcpTunnelId(pub String);

impl fmt::Display for TcpTunnelId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0)
    }
}

impl From<String> for TcpTunnelId {
    fn from(s: String) -> Self {
        TcpTunnelId(s)
    }
}

/// Unique identifier for a TCP connection
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(transparent)]
pub struct TcpId(pub String);

impl fmt::Display for TcpId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0)
    }
}

impl From<String> for TcpId {
    fn from(s: String) -> Self {
        TcpId(s)
    }
}
