use thiserror::Error;

#[allow(dead_code)]
#[derive(Error, Debug)]
pub enum BurrowError {
    #[error("JSON error: {0}")]
    Json(#[from] serde_json::Error),

    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("Crypto error: {0}")]
    Crypto(String),
}

#[allow(dead_code)]
pub type Result<T> = std::result::Result<T, BurrowError>;
