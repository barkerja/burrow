use anyhow::Result;
use base64::Engine;
use futures_util::{SinkExt, StreamExt};
use std::sync::Arc;
use tokio::sync::{mpsc, Mutex};
use tokio_tungstenite::{
    connect_async,
    tungstenite::{client::IntoClientRequest, Message},
};
use tracing::{debug, info};

use crate::protocol::{OutgoingMessage, WsId};

/// Proxy for WebSocket connections between server and local service
pub struct WebSocketProxy {
    /// Channel to send frames from server to local
    to_local_tx: mpsc::Sender<(String, Vec<u8>)>,
    /// Channel to receive frames from local to send to server
    from_local_rx: Arc<Mutex<mpsc::Receiver<Message>>>,
    /// Channel to send messages to server
    msg_tx: mpsc::Sender<String>,
}

impl WebSocketProxy {
    /// Connect to a local WebSocket endpoint
    pub async fn connect(
        local_host: &str,
        local_port: u16,
        path: &str,
        headers: Vec<Vec<String>>,
        msg_tx: mpsc::Sender<String>,
    ) -> Result<Self> {
        // Build WebSocket URL
        let url = format!("ws://{}:{}{}", local_host, local_port, path);
        debug!("Connecting to local WebSocket: {}", url);

        // Build request using IntoClientRequest to get proper WebSocket headers
        let mut request = url.into_client_request()?;

        // Forward cookies if present (important for session auth)
        for header in &headers {
            if header.len() >= 2 {
                let name_lower = header[0].to_lowercase();
                // Only forward cookie and authorization headers
                if name_lower == "cookie" || name_lower == "authorization" {
                    if let (Ok(name), Ok(value)) = (
                        header[0].parse::<http::header::HeaderName>(),
                        header[1].parse(),
                    ) {
                        request.headers_mut().insert(name, value);
                    }
                }
            }
        }

        // Connect to local WebSocket
        let (ws_stream, response) = connect_async(request).await?;
        info!("Local WebSocket connected, status: {}", response.status());
        let (write, read) = ws_stream.split();

        // Create channels
        let (to_local_tx, to_local_rx) = mpsc::channel::<(String, Vec<u8>)>(64);
        let (from_local_tx, from_local_rx) = mpsc::channel::<Message>(64);

        // Spawn task to forward from to_local channel to WebSocket
        // This task exclusively owns the write half - no locks needed
        tokio::spawn(async move {
            let mut write = write;
            let mut rx = to_local_rx;
            while let Some((opcode, data)) = rx.recv().await {
                let msg = match opcode.as_str() {
                    "text" => Message::Text(String::from_utf8_lossy(&data).to_string()),
                    "binary" => Message::Binary(data),
                    "ping" => Message::Ping(data),
                    "pong" => Message::Pong(data),
                    "close" => Message::Close(None),
                    _ => Message::Binary(data),
                };

                if write.send(msg).await.is_err() {
                    break;
                }
            }
        });

        // Spawn task to read from WebSocket and send to channel
        tokio::spawn(async move {
            let mut read = read;
            while let Some(result) = read.next().await {
                match result {
                    Ok(msg) => {
                        if from_local_tx.send(msg).await.is_err() {
                            break;
                        }
                    }
                    Err(e) => {
                        debug!("WebSocket read error: {}", e);
                        break;
                    }
                }
            }
        });

        Ok(Self {
            to_local_tx,
            from_local_rx: Arc::new(Mutex::new(from_local_rx)),
            msg_tx,
        })
    }

    /// Send a frame from server to local
    pub async fn send_to_local(&self, opcode: &str, data: Vec<u8>) {
        let _ = self.to_local_tx.send((opcode.to_string(), data)).await;
    }

    /// Close the local WebSocket connection
    pub async fn close(&self, _code: u16, _reason: &str) {
        // Send close through the channel to avoid lock-across-await
        let _ = self.to_local_tx.send(("close".to_string(), vec![])).await;
    }

    /// Run the proxy, forwarding frames from local to server
    pub async fn run(&self, ws_id: &WsId) {
        let mut rx = self.from_local_rx.lock().await;

        while let Some(msg) = rx.recv().await {
            let result = match msg {
                Message::Text(text) => {
                    let msg = OutgoingMessage::WsFrame {
                        ws_id: ws_id.clone(),
                        opcode: "text".to_string(),
                        data: text,
                        data_encoding: None,
                    };
                    msg.to_json()
                        .map(|json| self.msg_tx.try_send(json).ok())
                        .ok()
                }
                Message::Binary(data) => {
                    let msg = OutgoingMessage::WsFrame {
                        ws_id: ws_id.clone(),
                        opcode: "binary".to_string(),
                        data: base64::engine::general_purpose::STANDARD.encode(&data),
                        data_encoding: Some("base64".to_string()),
                    };
                    msg.to_json()
                        .map(|json| self.msg_tx.try_send(json).ok())
                        .ok()
                }
                Message::Ping(data) => {
                    let msg = OutgoingMessage::WsFrame {
                        ws_id: ws_id.clone(),
                        opcode: "ping".to_string(),
                        data: base64::engine::general_purpose::STANDARD.encode(&data),
                        data_encoding: Some("base64".to_string()),
                    };
                    msg.to_json()
                        .map(|json| self.msg_tx.try_send(json).ok())
                        .ok()
                }
                Message::Pong(data) => {
                    let msg = OutgoingMessage::WsFrame {
                        ws_id: ws_id.clone(),
                        opcode: "pong".to_string(),
                        data: base64::engine::general_purpose::STANDARD.encode(&data),
                        data_encoding: Some("base64".to_string()),
                    };
                    msg.to_json()
                        .map(|json| self.msg_tx.try_send(json).ok())
                        .ok()
                }
                Message::Close(frame) => {
                    let (code, reason) = frame
                        .map(|f| (f.code.into(), f.reason.to_string()))
                        .unwrap_or((1000, String::new()));

                    let msg = OutgoingMessage::WsClose {
                        ws_id: ws_id.clone(),
                        code,
                        reason,
                    };
                    msg.to_json()
                        .map(|json| self.msg_tx.try_send(json).ok())
                        .ok();
                    break;
                }
                _ => None,
            };

            if result.is_none() {
                break;
            }
        }
    }
}
