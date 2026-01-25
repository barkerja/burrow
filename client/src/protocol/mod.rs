//! Protocol message types for tunnel communication.
//!
//! Defines the JSON message format used between client and server:
//! - [`OutgoingMessage`] - Messages sent from client to server
//! - [`IncomingMessage`] - Messages received from server
//!
//! Also provides type-safe ID wrappers for compile-time safety.

mod ids;
mod messages;

pub use ids::*;
pub use messages::*;
