use serde::{Deserialize, Serialize};

use super::ids::{RequestId, TcpId, TcpTunnelId, TunnelId, WsId};

/// Outgoing message types (Client -> Server)
#[derive(Debug, Clone, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum OutgoingMessage {
    RegisterTunnel {
        token: String,
        local_host: String,
        local_port: u16,
        #[serde(skip_serializing_if = "Option::is_none")]
        requested_subdomain: Option<String>,
    },
    TunnelResponse {
        request_id: RequestId,
        status: u16,
        headers: Vec<[String; 2]>,
        #[serde(skip_serializing_if = "Option::is_none")]
        body: Option<String>,
        #[serde(skip_serializing_if = "Option::is_none")]
        body_encoding: Option<String>,
    },
    WsUpgraded {
        ws_id: WsId,
        headers: Vec<[String; 2]>,
    },
    WsFrame {
        ws_id: WsId,
        opcode: String,
        data: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        data_encoding: Option<String>,
    },
    WsClose {
        ws_id: WsId,
        code: u16,
        reason: String,
    },
    RegisterTcpTunnel {
        local_port: u16,
    },
    TcpConnected {
        tcp_id: TcpId,
    },
    TcpData {
        tcp_id: TcpId,
        data: String,
        data_encoding: String,
    },
    TcpClose {
        tcp_id: TcpId,
        reason: String,
    },
    Heartbeat {},
}

/// Incoming message types (Server -> Client)
#[derive(Debug, Clone, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum IncomingMessage {
    TunnelRegistered {
        tunnel_id: TunnelId,
        #[allow(dead_code)]
        subdomain: String,
        full_url: String,
    },
    TunnelRequest {
        request_id: RequestId,
        tunnel_id: TunnelId,
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
        ws_id: WsId,
        tunnel_id: TunnelId,
        path: String,
        headers: Vec<Vec<String>>,
    },
    WsFrame {
        ws_id: WsId,
        opcode: String,
        data: String,
        #[serde(default)]
        data_encoding: Option<String>,
    },
    WsClose {
        ws_id: WsId,
        #[serde(default)]
        code: Option<u16>,
        #[serde(default)]
        reason: Option<String>,
    },
    TcpTunnelRegistered {
        tcp_tunnel_id: TcpTunnelId,
        server_port: u16,
        local_port: u16,
    },
    TcpConnect {
        tcp_id: TcpId,
        tcp_tunnel_id: TcpTunnelId,
    },
    TcpData {
        tcp_id: TcpId,
        data: String,
        #[serde(default)]
        data_encoding: Option<String>,
    },
    TcpClose {
        tcp_id: TcpId,
    },
    Heartbeat {},
    Error {
        code: String,
        message: String,
    },
}

impl OutgoingMessage {
    pub fn register_tunnel(
        token: &str,
        local_host: &str,
        local_port: u16,
        requested_subdomain: Option<String>,
    ) -> Self {
        OutgoingMessage::RegisterTunnel {
            token: token.to_string(),
            local_host: local_host.to_string(),
            local_port,
            requested_subdomain,
        }
    }

    pub fn tunnel_response(
        request_id: &RequestId,
        status: u16,
        headers: Vec<(String, String)>,
        body: Option<Vec<u8>>,
    ) -> Self {
        let (body_str, encoding) = encode_body(body);
        OutgoingMessage::TunnelResponse {
            request_id: request_id.clone(),
            status,
            headers: headers.into_iter().map(|(k, v)| [k, v]).collect(),
            body: body_str,
            body_encoding: encoding,
        }
    }

    pub fn register_tcp_tunnel(local_port: u16) -> Self {
        OutgoingMessage::RegisterTcpTunnel { local_port }
    }

    pub fn tcp_connected(tcp_id: &TcpId) -> Self {
        OutgoingMessage::TcpConnected {
            tcp_id: tcp_id.clone(),
        }
    }

    pub fn tcp_data(tcp_id: &TcpId, data: &[u8]) -> Self {
        OutgoingMessage::TcpData {
            tcp_id: tcp_id.clone(),
            data: base64::Engine::encode(&base64::engine::general_purpose::STANDARD, data),
            data_encoding: "base64".to_string(),
        }
    }

    pub fn tcp_close(tcp_id: &TcpId, reason: &str) -> Self {
        OutgoingMessage::TcpClose {
            tcp_id: tcp_id.clone(),
            reason: reason.to_string(),
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
                    let encoded =
                        base64::Engine::encode(&base64::engine::general_purpose::STANDARD, &data);
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
