use anyhow::{Context, Result};
use base64::Engine;
use chrono::Local;
use futures_util::{FutureExt, SinkExt, StreamExt};
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio::sync::{mpsc, Mutex, RwLock};
use tokio_tungstenite::{connect_async, tungstenite::Message};
use tracing::{debug, error, info, warn};

use crate::crypto::{create_attestation, Keypair};
use crate::protocol::{decode_body, IncomingMessage, OutgoingMessage};

use super::http_proxy::forward_http_request;
use super::tui::{
    ConnectionStatus, RequestEvent, ResponseEvent, TcpTunnelEvent, TuiEvent, TunnelEvent,
};
use super::ws_proxy::WebSocketProxy;

/// Information about a registered tunnel
#[derive(Debug, Clone)]
#[allow(dead_code)]
pub struct TunnelInfo {
    pub tunnel_id: String,
    pub subdomain: String,
    pub full_url: String,
    pub local_host: String,
    pub local_port: u16,
}

/// Information about a registered TCP tunnel
#[derive(Debug, Clone)]
#[allow(dead_code)]
pub struct TcpTunnelInfo {
    pub tcp_tunnel_id: String,
    pub server_port: u16,
    pub local_port: u16,
}

/// Pending tunnel registration
#[allow(dead_code)]
struct PendingTunnel {
    local_host: String,
    local_port: u16,
    subdomain: Option<String>,
}

/// Active TCP connection state
struct TcpConnection {
    tx: mpsc::Sender<Vec<u8>>,
}

/// Shared state for the tunnel client
#[allow(dead_code)]
struct ClientState {
    /// Registered HTTP tunnels (tunnel_id -> info)
    tunnels: HashMap<String, TunnelInfo>,
    /// Pending HTTP tunnel registrations (index -> pending info)
    pending_tunnels: Vec<PendingTunnel>,
    /// Registered TCP tunnels (tcp_tunnel_id -> info)
    tcp_tunnels: HashMap<String, TcpTunnelInfo>,
    /// Pending TCP tunnel registrations (local_port -> waiting)
    pending_tcp_tunnels: Vec<u16>,
    /// Active TCP connections (tcp_id -> connection)
    tcp_connections: HashMap<String, TcpConnection>,
    /// Active WebSocket proxies (ws_id -> proxy)
    ws_proxies: HashMap<String, Arc<WebSocketProxy>>,
    /// Server host for display
    server_host: String,
    /// Local host for forwarding
    local_host: String,
}

impl ClientState {
    fn new(server_host: &str, local_host: &str) -> Self {
        Self {
            tunnels: HashMap::new(),
            pending_tunnels: Vec::new(),
            tcp_tunnels: HashMap::new(),
            pending_tcp_tunnels: Vec::new(),
            tcp_connections: HashMap::new(),
            ws_proxies: HashMap::new(),
            server_host: server_host.to_string(),
            local_host: local_host.to_string(),
        }
    }

    fn find_tunnel_port(&self, tunnel_id: &str) -> Option<u16> {
        self.tunnels.get(tunnel_id).map(|t| t.local_port)
    }

    fn find_tcp_tunnel(&self, tcp_tunnel_id: &str) -> Option<&TcpTunnelInfo> {
        self.tcp_tunnels.get(tcp_tunnel_id)
    }
}

pub struct TunnelClient {
    server_host: String,
    server_port: u16,
    local_host: String,
    tunnels: Vec<(u16, Option<String>)>,
    tcp_ports: Vec<u16>,
    keypair_path: Option<PathBuf>,
    tui_tx: Option<mpsc::Sender<TuiEvent>>,
}

impl TunnelClient {
    pub fn new(
        server_host: &str,
        server_port: u16,
        local_host: &str,
        tunnels: Vec<(u16, Option<String>)>,
        tcp_ports: Vec<u16>,
        keypair_path: Option<String>,
        tui_tx: Option<mpsc::Sender<TuiEvent>>,
    ) -> Result<Self> {
        Ok(Self {
            server_host: server_host.to_string(),
            server_port,
            local_host: local_host.to_string(),
            tunnels,
            tcp_ports,
            keypair_path: keypair_path.map(PathBuf::from),
            tui_tx,
        })
    }

    pub async fn run(&self) -> Result<()> {
        // Load or generate keypair
        let keypair_path = self
            .keypair_path
            .clone()
            .unwrap_or_else(crate::crypto::keypair::default_keypair_path);

        info!("Using keypair: {}", keypair_path.display());
        let keypair = Keypair::load_or_generate(&keypair_path)
            .context("Failed to load or generate keypair")?;

        // Reconnection loop with exponential backoff
        let mut retry_delay = Duration::from_secs(1);
        let max_delay = Duration::from_secs(60);

        loop {
            self.send_tui_event(TuiEvent::ConnectionStatus(ConnectionStatus::Connecting))
                .await;

            match self.connect_and_run(&keypair).await {
                Ok(()) => {
                    info!("Connection closed normally");
                    self.send_tui_event(TuiEvent::ConnectionStatus(ConnectionStatus::Disconnected))
                        .await;
                    break;
                }
                Err(e) => {
                    error!("Connection error: {}", e);
                    self.send_tui_event(TuiEvent::ConnectionStatus(ConnectionStatus::Reconnecting))
                        .await;
                    info!("Reconnecting in {:?}...", retry_delay);
                    tokio::time::sleep(retry_delay).await;

                    // Exponential backoff
                    retry_delay = std::cmp::min(retry_delay * 2, max_delay);
                }
            }

            // Check for shutdown signal
            if tokio::signal::ctrl_c().now_or_never().is_some() {
                info!("Shutdown requested");
                self.send_tui_event(TuiEvent::Shutdown).await;
                break;
            }
        }

        Ok(())
    }

    async fn send_tui_event(&self, event: TuiEvent) {
        if let Some(tx) = &self.tui_tx {
            let _ = tx.send(event).await;
        }
    }

    async fn connect_and_run(&self, keypair: &Keypair) -> Result<()> {
        // Connect to server
        let ws_url = format!("wss://{}:{}/tunnel/ws", self.server_host, self.server_port);
        info!("Connecting to {}...", ws_url);

        let (ws_stream, _) = connect_async(&ws_url)
            .await
            .context("Failed to connect to server")?;

        info!("Connected to server");
        self.send_tui_event(TuiEvent::ConnectionStatus(ConnectionStatus::Connected))
            .await;

        // Split the stream
        let (write, read) = ws_stream.split();
        let write = Arc::new(Mutex::new(write));

        // Create message channel
        let (msg_tx, mut msg_rx) = mpsc::channel::<String>(256);

        // Initialize state
        let state = Arc::new(RwLock::new(ClientState::new(
            &self.server_host,
            &self.local_host,
        )));

        // Set up pending tunnels
        {
            let mut s = state.write().await;
            for (port, subdomain) in &self.tunnels {
                s.pending_tunnels.push(PendingTunnel {
                    local_host: self.local_host.clone(),
                    local_port: *port,
                    subdomain: subdomain.clone(),
                });
            }
            s.pending_tcp_tunnels = self.tcp_ports.clone();
        }

        // Register HTTP tunnels
        for (i, (local_port, subdomain)) in self.tunnels.iter().enumerate() {
            let attestation = create_attestation(keypair, subdomain.as_deref());
            let msg =
                OutgoingMessage::register_tunnel(attestation, &self.local_host, *local_port);
            let json = msg.to_json()?;

            let mut write_guard = write.lock().await;
            write_guard.send(Message::Text(json)).await?;
            drop(write_guard);

            debug!("Sent register_tunnel {} for port {}", i, local_port);
        }

        // Channel for raw WebSocket messages (including pong frames)
        let (ws_tx, mut ws_rx) = mpsc::channel::<Message>(256);

        // Spawn message sender task
        let write_clone = write.clone();
        let sender_handle = tokio::spawn(async move {
            while let Some(msg) = ws_rx.recv().await {
                let mut write_guard = write_clone.lock().await;
                if let Err(e) = write_guard.send(msg).await {
                    // Only log if it's not a normal close
                    if !e.to_string().contains("closing") {
                        debug!("Send error (connection closing): {}", e);
                    }
                    break;
                }
            }
        });

        // Bridge text messages to WebSocket messages
        let ws_tx_clone = ws_tx.clone();
        let text_bridge_handle = tokio::spawn(async move {
            while let Some(text) = msg_rx.recv().await {
                if ws_tx_clone.send(Message::Text(text)).await.is_err() {
                    break;
                }
            }
        });

        // Spawn message receiver task
        let state_clone = state.clone();
        let msg_tx_clone = msg_tx.clone();
        let server_host = self.server_host.clone();
        let ws_tx_for_pong = ws_tx.clone();
        let tui_tx_clone = self.tui_tx.clone();

        let receiver_handle = tokio::spawn(async move {
            let mut read = read;
            let mut tunnels_registered = 0;
            let mut tcp_tunnels_registered = 0;

            while let Some(result) = read.next().await {
                match result {
                    Ok(Message::Text(text)) => {
                        if let Err(e) = handle_message(
                            &text,
                            &state_clone,
                            &msg_tx_clone,
                            &server_host,
                            &mut tunnels_registered,
                            &mut tcp_tunnels_registered,
                            &tui_tx_clone,
                        )
                        .await
                        {
                            error!("Error handling message: {}", e);
                        }
                    }
                    Ok(Message::Ping(data)) => {
                        debug!("Received ping, sending pong");
                        let _ = ws_tx_for_pong.send(Message::Pong(data)).await;
                    }
                    Ok(Message::Pong(_)) => {
                        debug!("Received pong");
                    }
                    Ok(Message::Close(frame)) => {
                        info!(
                            "Server closed connection: {:?}",
                            frame.map(|f| f.reason.to_string())
                        );
                        break;
                    }
                    Ok(Message::Binary(_)) => {
                        debug!("Received binary message (ignoring)");
                    }
                    Err(e) => {
                        debug!("WebSocket read error: {}", e);
                        break;
                    }
                    _ => {}
                }
            }
        });

        // Drop the senders to signal tasks to stop when we're done
        drop(msg_tx);
        drop(ws_tx);

        // Wait for shutdown or disconnect
        tokio::select! {
            _ = sender_handle => {
                debug!("Sender task ended");
            }
            _ = text_bridge_handle => {
                debug!("Text bridge task ended");
            }
            _ = receiver_handle => {
                debug!("Receiver task ended");
            }
            _ = tokio::signal::ctrl_c() => {
                info!("\nShutting down...");
                return Ok(());
            }
        }

        // If we get here, connection was lost
        Err(anyhow::anyhow!("Connection lost"))
    }
}

async fn handle_message(
    text: &str,
    state: &Arc<RwLock<ClientState>>,
    msg_tx: &mpsc::Sender<String>,
    server_host: &str,
    tunnels_registered: &mut usize,
    tcp_tunnels_registered: &mut usize,
    tui_tx: &Option<mpsc::Sender<TuiEvent>>,
) -> Result<()> {
    let msg = IncomingMessage::from_json(text).context("Failed to parse message")?;

    match msg {
        IncomingMessage::TunnelRegistered {
            tunnel_id,
            subdomain,
            full_url,
        } => {
            let mut s = state.write().await;

            // Find the pending tunnel for this registration
            let pending = s.pending_tunnels.get(*tunnels_registered);
            let (local_host, local_port) = pending
                .map(|p| (p.local_host.clone(), p.local_port))
                .unwrap_or_else(|| (s.local_host.clone(), 0));

            info!("Tunnel registered: {} -> {}:{}", full_url, local_host, local_port);

            // Send TUI event
            if let Some(tx) = tui_tx {
                let _ = tx
                    .send(TuiEvent::TunnelRegistered(TunnelEvent {
                        full_url: full_url.clone(),
                        local_port,
                    }))
                    .await;
            }

            s.tunnels.insert(
                tunnel_id.clone(),
                TunnelInfo {
                    tunnel_id,
                    subdomain,
                    full_url,
                    local_host,
                    local_port,
                },
            );

            *tunnels_registered += 1;

            // Register TCP tunnels after first HTTP tunnel
            if *tunnels_registered == 1 && !s.pending_tcp_tunnels.is_empty() {
                for tcp_port in &s.pending_tcp_tunnels.clone() {
                    let msg = OutgoingMessage::register_tcp_tunnel(*tcp_port);
                    if let Ok(json) = msg.to_json() {
                        let _ = msg_tx.send(json).await;
                    }
                }
            }

            // Print status once all HTTP tunnels are registered (only in non-TUI mode)
            if tui_tx.is_none()
                && *tunnels_registered == s.pending_tunnels.len()
                && s.pending_tcp_tunnels.is_empty()
            {
                print_status(&s, server_host);
            }
        }

        IncomingMessage::TcpTunnelRegistered {
            tcp_tunnel_id,
            server_port,
            local_port,
        } => {
            let mut s = state.write().await;

            info!(
                "TCP tunnel registered: {}:{} -> localhost:{}",
                server_host, server_port, local_port
            );

            // Send TUI event
            if let Some(tx) = tui_tx {
                let _ = tx
                    .send(TuiEvent::TcpTunnelRegistered(TcpTunnelEvent {
                        server_port,
                        local_port,
                    }))
                    .await;
            }

            s.tcp_tunnels.insert(
                tcp_tunnel_id.clone(),
                TcpTunnelInfo {
                    tcp_tunnel_id,
                    server_port,
                    local_port,
                },
            );

            *tcp_tunnels_registered += 1;

            // Print status once all tunnels are registered (only in non-TUI mode)
            if tui_tx.is_none()
                && *tunnels_registered == s.pending_tunnels.len()
                && *tcp_tunnels_registered == s.pending_tcp_tunnels.len()
            {
                print_status(&s, server_host);
            }
        }

        IncomingMessage::TunnelRequest {
            request_id,
            tunnel_id,
            method,
            path,
            query_string,
            headers,
            body,
            body_encoding,
            client_ip,
        } => {
            let s = state.read().await;
            let local_port = s.find_tunnel_port(&tunnel_id).unwrap_or(3000);
            let local_host = s.local_host.clone();
            drop(s);

            debug!("{} {} -> localhost:{}", method, path, local_port);

            let msg_tx = msg_tx.clone();
            let body_data = decode_body(body.as_deref(), body_encoding.as_deref());

            // Convert headers
            let headers: Vec<(String, String)> = headers
                .into_iter()
                .filter_map(|h| {
                    if h.len() >= 2 {
                        Some((h[0].clone(), h[1].clone()))
                    } else {
                        None
                    }
                })
                .collect();

            // Send TUI request event
            if let Some(tx) = tui_tx {
                let _ = tx
                    .send(TuiEvent::RequestReceived(RequestEvent {
                        request_id: request_id.clone(),
                        method: method.clone(),
                        path: path.clone(),
                        query_string: query_string.clone(),
                        headers: headers.clone(),
                        body: body_data.clone(),
                        timestamp: Local::now(),
                        client_ip,
                    }))
                    .await;
            }

            let tui_tx_clone = tui_tx.clone();
            let request_id_clone = request_id.clone();
            let method_clone = method.clone();
            let path_clone = path.clone();

            tokio::spawn(async move {
                let start = Instant::now();
                let response = forward_http_request(
                    &local_host,
                    local_port,
                    &method_clone,
                    &path_clone,
                    &query_string,
                    headers,
                    body_data,
                )
                .await;

                let duration_ms = start.elapsed().as_millis() as u64;

                let msg = match response {
                    Ok((status, headers, body)) => {
                        debug!(
                            "{} {} -> {} {}",
                            method_clone,
                            path_clone,
                            status,
                            body.as_ref().map(|b| b.len()).unwrap_or(0)
                        );

                        // Send TUI response event
                        if let Some(tx) = &tui_tx_clone {
                            let _ = tx
                                .send(TuiEvent::ResponseSent(ResponseEvent {
                                    request_id: request_id_clone.clone(),
                                    status,
                                    headers: headers.clone(),
                                    body: body.clone(),
                                    duration_ms,
                                }))
                                .await;
                        }

                        OutgoingMessage::tunnel_response(&request_id_clone, status, headers, body)
                    }
                    Err(e) => {
                        warn!("{} {} -> error: {}", method_clone, path_clone, e);

                        // Send TUI error response event
                        if let Some(tx) = &tui_tx_clone {
                            let _ = tx
                                .send(TuiEvent::ResponseSent(ResponseEvent {
                                    request_id: request_id_clone.clone(),
                                    status: 502,
                                    headers: vec![("content-type".to_string(), "text/plain".to_string())],
                                    body: Some(format!("Bad Gateway: {}", e).into_bytes()),
                                    duration_ms,
                                }))
                                .await;
                        }

                        OutgoingMessage::tunnel_response(
                            &request_id_clone,
                            502,
                            vec![("content-type".to_string(), "text/plain".to_string())],
                            Some(format!("Bad Gateway: {}", e).into_bytes()),
                        )
                    }
                };

                if let Ok(json) = msg.to_json() {
                    let _ = msg_tx.send(json).await;
                }
            });
        }

        IncomingMessage::WsUpgrade {
            ws_id,
            tunnel_id,
            path,
            headers,
        } => {
            let s = state.read().await;
            let local_port = s.find_tunnel_port(&tunnel_id).unwrap_or(3000);
            let local_host = s.local_host.clone();
            drop(s);

            info!("WebSocket upgrade request: {} -> localhost:{}", ws_id, local_port);
            debug!("WebSocket path: {}", path);

            let msg_tx = msg_tx.clone();
            let state_clone = state.clone();
            let ws_id_clone = ws_id.clone();

            tokio::spawn(async move {
                match WebSocketProxy::connect(&local_host, local_port, &path, headers, msg_tx.clone()).await {
                    Ok(proxy) => {
                        info!("WebSocket connected: {} -> localhost:{}", ws_id_clone, local_port);
                        // Send ws_upgraded
                        let msg = OutgoingMessage::WsUpgraded {
                            ws_id: ws_id_clone.clone(),
                            headers: vec![], // Local WS libs don't typically expose response headers
                        };
                        if let Ok(json) = msg.to_json() {
                            let _ = msg_tx.send(json).await;
                        }

                        // Store proxy
                        let proxy = Arc::new(proxy);
                        {
                            let mut s = state_clone.write().await;
                            s.ws_proxies.insert(ws_id_clone.clone(), proxy.clone());
                        }

                        // Start forwarding
                        proxy.run(&ws_id_clone).await;

                        // Clean up
                        {
                            let mut s = state_clone.write().await;
                            s.ws_proxies.remove(&ws_id_clone);
                        }
                    }
                    Err(e) => {
                        error!("WebSocket upgrade failed for {}: {}", ws_id_clone, e);
                        let msg = OutgoingMessage::WsClose {
                            ws_id: ws_id_clone,
                            code: 1011,
                            reason: format!("Local connection failed: {}", e),
                        };
                        if let Ok(json) = msg.to_json() {
                            let _ = msg_tx.send(json).await;
                        }
                    }
                }
            });
        }

        IncomingMessage::WsFrame {
            ws_id,
            opcode,
            data,
            data_encoding,
        } => {
            let s = state.read().await;
            if let Some(proxy) = s.ws_proxies.get(&ws_id) {
                let decoded = if data_encoding.as_deref() == Some("base64") {
                    base64::engine::general_purpose::STANDARD
                        .decode(&data)
                        .unwrap_or_else(|_| data.into_bytes())
                } else {
                    data.into_bytes()
                };
                proxy.send_to_local(&opcode, decoded).await;
            }
        }

        IncomingMessage::WsClose { ws_id, code, reason } => {
            let mut s = state.write().await;
            if let Some(proxy) = s.ws_proxies.remove(&ws_id) {
                proxy.close(code.unwrap_or(1000), reason.as_deref().unwrap_or("")).await;
            }
        }

        IncomingMessage::TcpConnect {
            tcp_id,
            tcp_tunnel_id,
        } => {
            let s = state.read().await;
            let local_port = s.find_tcp_tunnel(&tcp_tunnel_id).map(|t| t.local_port);
            drop(s);

            if let Some(local_port) = local_port {
                info!("TCP connect: {} -> localhost:{}", tcp_id, local_port);

                let msg_tx = msg_tx.clone();
                let state_clone = state.clone();
                let tcp_id_clone = tcp_id.clone();

                tokio::spawn(async move {
                    match TcpStream::connect(format!("localhost:{}", local_port)).await {
                        Ok(stream) => {
                            info!("TCP connected to localhost:{}, starting forwarding", local_port);
                            // Send tcp_connected
                            let msg = OutgoingMessage::tcp_connected(&tcp_id_clone);
                            if let Ok(json) = msg.to_json() {
                                let _ = msg_tx.send(json).await;
                            }

                            // Start bidirectional forwarding
                            handle_tcp_connection(stream, &tcp_id_clone, msg_tx, state_clone).await;
                        }
                        Err(e) => {
                            error!("TCP connect failed for {}: {}", tcp_id_clone, e);
                            let msg = OutgoingMessage::tcp_close(
                                &tcp_id_clone,
                                &format!("Connection failed: {}", e),
                            );
                            if let Ok(json) = msg.to_json() {
                                let _ = msg_tx.send(json).await;
                            }
                        }
                    }
                });
            } else {
                warn!("TCP tunnel not found: {}", tcp_tunnel_id);
            }
        }

        IncomingMessage::TcpData {
            tcp_id,
            data,
            data_encoding,
        } => {
            let s = state.read().await;
            if let Some(conn) = s.tcp_connections.get(&tcp_id) {
                let decoded = if data_encoding.as_deref() == Some("base64") {
                    base64::engine::general_purpose::STANDARD
                        .decode(&data)
                        .unwrap_or_default()
                } else {
                    data.into_bytes()
                };
                debug!("TCP data received for {}: {} bytes", tcp_id, decoded.len());
                let _ = conn.tx.send(decoded).await;
            } else {
                warn!("TCP data for unknown connection: {}", tcp_id);
            }
        }

        IncomingMessage::TcpClose { tcp_id, .. } => {
            let mut s = state.write().await;
            s.tcp_connections.remove(&tcp_id);
            info!("TCP connection closed: {}", tcp_id);
        }

        IncomingMessage::Heartbeat { .. } => {
            debug!("Received heartbeat");
        }

        IncomingMessage::Error { code, message } => {
            error!("Server error: {} - {}", code, message);
        }
    }

    Ok(())
}

async fn handle_tcp_connection(
    stream: TcpStream,
    tcp_id: &str,
    msg_tx: mpsc::Sender<String>,
    state: Arc<RwLock<ClientState>>,
) {
    let (mut read_half, mut write_half) = stream.into_split();

    // Create channel for data from server to local
    let (local_tx, mut local_rx) = mpsc::channel::<Vec<u8>>(64);

    // Store connection
    {
        let mut s = state.write().await;
        s.tcp_connections
            .insert(tcp_id.to_string(), TcpConnection { tx: local_tx });
    }

    let tcp_id_owned = tcp_id.to_string();
    let msg_tx_clone = msg_tx.clone();

    // Task to read from local and send to server
    let read_task = tokio::spawn(async move {
        let mut buf = [0u8; 8192];
        loop {
            match read_half.read(&mut buf).await {
                Ok(0) => {
                    // Connection closed
                    let msg = OutgoingMessage::tcp_close(&tcp_id_owned, "closed");
                    if let Ok(json) = msg.to_json() {
                        let _ = msg_tx_clone.send(json).await;
                    }
                    break;
                }
                Ok(n) => {
                    let msg = OutgoingMessage::tcp_data(&tcp_id_owned, &buf[..n]);
                    if let Ok(json) = msg.to_json() {
                        if msg_tx_clone.send(json).await.is_err() {
                            break;
                        }
                    }
                }
                Err(e) => {
                    debug!("TCP read error: {}", e);
                    let msg = OutgoingMessage::tcp_close(&tcp_id_owned, &e.to_string());
                    if let Ok(json) = msg.to_json() {
                        let _ = msg_tx_clone.send(json).await;
                    }
                    break;
                }
            }
        }
    });

    // Task to write data from server to local
    let write_task = tokio::spawn(async move {
        while let Some(data) = local_rx.recv().await {
            if write_half.write_all(&data).await.is_err() {
                break;
            }
        }
    });

    // Wait for either task to complete
    tokio::select! {
        _ = read_task => {}
        _ = write_task => {}
    }

    // Clean up
    {
        let mut s = state.write().await;
        s.tcp_connections.remove(tcp_id);
    }
}

fn print_status(state: &ClientState, server_host: &str) {
    println!();
    println!("=== Tunnels Active ===");
    println!();

    if !state.tunnels.is_empty() {
        println!("HTTP:");
        for info in state.tunnels.values() {
            println!(
                "  {} -> {}:{}",
                info.full_url, info.local_host, info.local_port
            );
        }
    }

    if !state.tcp_tunnels.is_empty() {
        println!();
        println!("TCP:");
        for info in state.tcp_tunnels.values() {
            println!(
                "  {}:{} -> localhost:{}",
                server_host, info.server_port, info.local_port
            );
        }
    }

    println!();
    println!("Press Ctrl+C to stop all tunnels.");
    println!();
}
