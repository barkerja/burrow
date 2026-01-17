use thiserror::Error;

#[derive(Error, Debug)]
#[allow(dead_code)]
pub enum BurrowError {
    #[error("Connection failed: {0}")]
    ConnectionFailed(String),

    #[error("Registration failed: {0}")]
    RegistrationFailed(String),

    #[error("WebSocket error: {0}")]
    WebSocket(#[from] tokio_tungstenite::tungstenite::Error),

    #[error("JSON error: {0}")]
    Json(#[from] serde_json::Error),

    #[error("HTTP error: {0}")]
    Http(#[from] reqwest::Error),

    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("Crypto error: {0}")]
    Crypto(String),

    #[error("Protocol error: {0}")]
    Protocol(String),

    #[error("Timeout")]
    Timeout,

    #[error("Not connected")]
    NotConnected,
}

pub type Result<T> = std::result::Result<T, BurrowError>;
