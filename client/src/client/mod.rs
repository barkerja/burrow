//! Tunnel client implementation.
//!
//! This module provides the core tunnel functionality:
//! - [`TunnelClient`] - Main client that manages tunnel connections
//! - HTTP proxy for forwarding requests to local services
//! - WebSocket proxy for bidirectional WebSocket tunneling
//! - TUI for interactive request inspection

mod connection;
mod http_proxy;
pub mod tui;
mod ws_proxy;

pub use connection::TunnelClient;
