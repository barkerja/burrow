use serde::{Deserialize, Serialize};

/// Attestation for client authentication
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Attestation {
    pub public_key: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub requested_subdomain: Option<String>,
    pub timestamp: u64,
    pub signature: String,
}

/// Outgoing message types (Client -> Server)
#[derive(Debug, Clone, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
#[allow(dead_code)]
pub enum OutgoingMessage {
    RegisterTunnel {
        attestation: Attestation,
        local_host: String,
        local_port: u16,
    },
    TunnelResponse {
        request_id: String,
        status: u16,
        headers: Vec<[String; 2]>,
        #[serde(skip_serializing_if = "Option::is_none")]
        body: Option<String>,
        #[serde(skip_serializing_if = "Option::is_none")]
        body_encoding: Option<String>,
    },
    WsUpgraded {
        ws_id: String,
        headers: Vec<[String; 2]>,
    },
    WsFrame {
        ws_id: String,
        opcode: String,
        data: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        data_encoding: Option<String>,
    },
    WsClose {
        ws_id: String,
        code: u16,
        reason: String,
    },
    RegisterTcpTunnel {
        local_port: u16,
    },
    TcpConnected {
        tcp_id: String,
    },
    TcpData {
        tcp_id: String,
        data: String,
        data_encoding: String,
    },
    TcpClose {
        tcp_id: String,
        reason: String,
    },
    Heartbeat {
        timestamp: u64,
    },
}

/// Incoming message types (Server -> Client)
#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum IncomingMessage {
    TunnelRegistered {
        tunnel_id: String,
        subdomain: String,
        full_url: String,
    },
    TunnelRequest {
        request_id: String,
        tunnel_id: String,
        method: String,
        path: String,
        query_string: String,
        headers: Vec<Vec<String>>,
        #[serde(default)]
        body: Option<String>,
        #[serde(default)]
        body_encoding: Option<String>,
        #[serde(default)]
        client_ip: Option<String>,
    },
    WsUpgrade {
        ws_id: String,
        tunnel_id: String,
        path: String,
        headers: Vec<Vec<String>>,
    },
    WsFrame {
        ws_id: String,
        opcode: String,
        data: String,
        #[serde(default)]
        data_encoding: Option<String>,
    },
    WsClose {
        ws_id: String,
        #[serde(default)]
        code: Option<u16>,
        #[serde(default)]
        reason: Option<String>,
    },
    TcpTunnelRegistered {
        tcp_tunnel_id: String,
        server_port: u16,
        local_port: u16,
    },
    TcpConnect {
        tcp_id: String,
        tcp_tunnel_id: String,
    },
    TcpData {
        tcp_id: String,
        data: String,
        #[serde(default)]
        data_encoding: Option<String>,
    },
    TcpClose {
        tcp_id: String,
        #[serde(default)]
        #[allow(dead_code)]
        reason: Option<String>,
    },
    Heartbeat {
        #[allow(dead_code)]
        timestamp: u64,
    },
    Error {
        code: String,
        message: String,
    },
}

impl OutgoingMessage {
    pub fn register_tunnel(attestation: Attestation, local_host: &str, local_port: u16) -> Self {
        OutgoingMessage::RegisterTunnel {
            attestation,
            local_host: local_host.to_string(),
            local_port,
        }
    }

    pub fn tunnel_response(
        request_id: &str,
        status: u16,
        headers: Vec<(String, String)>,
        body: Option<Vec<u8>>,
    ) -> Self {
        let (body_str, encoding) = encode_body(body);
        OutgoingMessage::TunnelResponse {
            request_id: request_id.to_string(),
            status,
            headers: headers.into_iter().map(|(k, v)| [k, v]).collect(),
            body: body_str,
            body_encoding: encoding,
        }
    }

    pub fn register_tcp_tunnel(local_port: u16) -> Self {
        OutgoingMessage::RegisterTcpTunnel { local_port }
    }

    pub fn tcp_connected(tcp_id: &str) -> Self {
        OutgoingMessage::TcpConnected {
            tcp_id: tcp_id.to_string(),
        }
    }

    pub fn tcp_data(tcp_id: &str, data: &[u8]) -> Self {
        OutgoingMessage::TcpData {
            tcp_id: tcp_id.to_string(),
            data: base64::Engine::encode(&base64::engine::general_purpose::STANDARD, data),
            data_encoding: "base64".to_string(),
        }
    }

    pub fn tcp_close(tcp_id: &str, reason: &str) -> Self {
        OutgoingMessage::TcpClose {
            tcp_id: tcp_id.to_string(),
            reason: reason.to_string(),
        }
    }

    #[allow(dead_code)]
    pub fn heartbeat() -> Self {
        OutgoingMessage::Heartbeat {
            timestamp: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_secs(),
        }
    }

    pub fn to_json(&self) -> Result<String, serde_json::Error> {
        serde_json::to_string(self)
    }
}

impl IncomingMessage {
    pub fn from_json(json: &str) -> Result<Self, serde_json::Error> {
        serde_json::from_str(json)
    }
}

fn encode_body(body: Option<Vec<u8>>) -> (Option<String>, Option<String>) {
    match body {
        None => (None, None),
        Some(data) if data.is_empty() => (Some(String::new()), None),
        Some(data) => {
            // Try to interpret as UTF-8 first
            match String::from_utf8(data.clone()) {
                Ok(s) => (Some(s), None),
                Err(_) => {
                    // Binary data, encode as base64
                    let encoded = base64::Engine::encode(
                        &base64::engine::general_purpose::STANDARD,
                        &data,
                    );
                    (Some(encoded), Some("base64".to_string()))
                }
            }
        }
    }
}

pub fn decode_body(body: Option<&str>, encoding: Option<&str>) -> Option<Vec<u8>> {
    let body = body?;

    match encoding {
        Some("base64") => {
            base64::Engine::decode(&base64::engine::general_purpose::STANDARD, body).ok()
        }
        _ => Some(body.as_bytes().to_vec()),
    }
}
