mod events;
mod ui;

pub use events::*;

use crate::protocol::RequestId;
use std::io;
use std::time::Duration;

use anyhow::Result;
use chrono::Local;
use crossterm::{
    event::{self, DisableMouseCapture, EnableMouseCapture, Event, KeyCode, KeyEventKind},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{backend::CrosstermBackend, widgets::TableState, Terminal};
use tokio::sync::mpsc;

/// A logged request with optional response
#[derive(Debug, Clone)]
pub struct RequestLog {
    pub id: RequestId,
    pub method: String,
    pub path: String,
    pub query_string: String,
    pub request_headers: Vec<(String, String)>,
    pub request_body: Option<Vec<u8>>,
    pub status: Option<u16>,
    pub response_headers: Vec<(String, String)>,
    pub response_body: Option<Vec<u8>>,
    pub duration_ms: Option<u64>,
    pub timestamp: chrono::DateTime<Local>,
    pub client_ip: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ViewMode {
    TunnelList,
    AddTunnel,
    RequestList,
    RequestDetail,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum TunnelType {
    #[default]
    Http,
    Tcp,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AddTunnelField {
    TunnelType,
    Port,
    Subdomain,
}

/// TUI application state
pub struct App {
    pub tunnels: Vec<TunnelEvent>,
    pub tcp_tunnels: Vec<TcpTunnelEvent>,
    pub requests: Vec<RequestLog>,
    pub table_state: TableState,
    pub tunnel_list_state: TableState,
    pub view_mode: ViewMode,
    pub connection_status: ConnectionStatus,
    pub should_quit: bool,
    max_requests: usize,

    // Add tunnel form state
    pub add_tunnel_type: TunnelType,
    pub add_tunnel_port: String,
    pub add_tunnel_subdomain: String,
    pub add_tunnel_field: AddTunnelField,
    pub add_tunnel_error: Option<String>,

    // Command channel to connection
    cmd_tx: mpsc::Sender<TuiCommand>,
}

impl App {
    pub fn new(cmd_tx: mpsc::Sender<TuiCommand>) -> Self {
        Self {
            tunnels: Vec::new(),
            tcp_tunnels: Vec::new(),
            requests: Vec::new(),
            table_state: TableState::default(),
            tunnel_list_state: TableState::default(),
            view_mode: ViewMode::TunnelList,
            connection_status: ConnectionStatus::Connecting,
            should_quit: false,
            max_requests: 1000,
            add_tunnel_type: TunnelType::Http,
            add_tunnel_port: String::new(),
            add_tunnel_subdomain: String::new(),
            add_tunnel_field: AddTunnelField::Port,
            add_tunnel_error: None,
            cmd_tx,
        }
    }

    pub fn next(&mut self) {
        if self.requests.is_empty() {
            return;
        }
        let i = match self.table_state.selected() {
            Some(i) => {
                if i >= self.requests.len() - 1 {
                    i // Stay at bottom
                } else {
                    i + 1
                }
            }
            None => 0,
        };
        self.table_state.select(Some(i));
    }

    pub fn previous(&mut self) {
        if self.requests.is_empty() {
            return;
        }
        let i = match self.table_state.selected() {
            Some(i) => i.saturating_sub(1), // Stay at top (saturating_sub prevents underflow)
            None => 0,
        };
        self.table_state.select(Some(i));
    }

    pub fn go_to_top(&mut self) {
        if !self.requests.is_empty() {
            self.table_state.select(Some(0));
        }
    }

    pub fn go_to_bottom(&mut self) {
        if !self.requests.is_empty() {
            self.table_state.select(Some(self.requests.len() - 1));
        }
    }

    pub fn enter_request_detail(&mut self) {
        if self.table_state.selected().is_some() {
            self.view_mode = ViewMode::RequestDetail;
        }
    }

    pub fn back(&mut self) {
        self.view_mode = match self.view_mode {
            ViewMode::RequestDetail => ViewMode::RequestList,
            ViewMode::RequestList => ViewMode::TunnelList,
            ViewMode::AddTunnel => ViewMode::TunnelList,
            ViewMode::TunnelList => ViewMode::TunnelList,
        };
    }

    pub fn clear(&mut self) {
        self.requests.clear();
        self.table_state.select(None);
    }

    // Tunnel list navigation
    pub fn tunnel_next(&mut self) {
        let total = self.tunnels.len() + self.tcp_tunnels.len();
        if total == 0 {
            return;
        }
        let i = match self.tunnel_list_state.selected() {
            Some(i) => {
                if i >= total - 1 {
                    i
                } else {
                    i + 1
                }
            }
            None => 0,
        };
        self.tunnel_list_state.select(Some(i));
    }

    pub fn tunnel_previous(&mut self) {
        let total = self.tunnels.len() + self.tcp_tunnels.len();
        if total == 0 {
            return;
        }
        let i = match self.tunnel_list_state.selected() {
            Some(i) => i.saturating_sub(1),
            None => 0,
        };
        self.tunnel_list_state.select(Some(i));
    }

    pub fn enter_add_tunnel(&mut self) {
        self.add_tunnel_type = TunnelType::Http;
        self.add_tunnel_port.clear();
        self.add_tunnel_subdomain.clear();
        self.add_tunnel_field = AddTunnelField::Port;
        self.add_tunnel_error = None;
        self.view_mode = ViewMode::AddTunnel;
    }

    pub fn view_tunnel_requests(&mut self) {
        // Switch to request list view
        self.view_mode = ViewMode::RequestList;
    }

    pub fn is_disconnected(&self) -> bool {
        matches!(
            self.connection_status,
            ConnectionStatus::Disconnected { .. }
        )
    }

    pub fn is_reconnecting(&self) -> bool {
        matches!(
            self.connection_status,
            ConnectionStatus::Reconnecting { .. }
        )
    }

    pub fn is_connected(&self) -> bool {
        matches!(self.connection_status, ConnectionStatus::Connected)
    }

    // Add tunnel form navigation
    pub fn form_next_field(&mut self) {
        self.add_tunnel_field = match self.add_tunnel_field {
            AddTunnelField::TunnelType => AddTunnelField::Port,
            AddTunnelField::Port => {
                if self.add_tunnel_type == TunnelType::Http {
                    AddTunnelField::Subdomain
                } else {
                    AddTunnelField::TunnelType
                }
            }
            AddTunnelField::Subdomain => AddTunnelField::TunnelType,
        };
    }

    pub fn form_prev_field(&mut self) {
        self.add_tunnel_field = match self.add_tunnel_field {
            AddTunnelField::TunnelType => {
                if self.add_tunnel_type == TunnelType::Http {
                    AddTunnelField::Subdomain
                } else {
                    AddTunnelField::Port
                }
            }
            AddTunnelField::Port => AddTunnelField::TunnelType,
            AddTunnelField::Subdomain => AddTunnelField::Port,
        };
    }

    pub fn form_toggle_type(&mut self) {
        self.add_tunnel_type = match self.add_tunnel_type {
            TunnelType::Http => TunnelType::Tcp,
            TunnelType::Tcp => TunnelType::Http,
        };
        // Clear subdomain when switching to TCP
        if self.add_tunnel_type == TunnelType::Tcp {
            self.add_tunnel_subdomain.clear();
            // If on subdomain field, move to port
            if self.add_tunnel_field == AddTunnelField::Subdomain {
                self.add_tunnel_field = AddTunnelField::Port;
            }
        }
    }

    pub fn form_input_char(&mut self, c: char) {
        match self.add_tunnel_field {
            AddTunnelField::Port => {
                if c.is_ascii_digit() && self.add_tunnel_port.len() < 5 {
                    self.add_tunnel_port.push(c);
                }
            }
            AddTunnelField::Subdomain => {
                if (c.is_ascii_alphanumeric() || c == '-') && self.add_tunnel_subdomain.len() < 32 {
                    self.add_tunnel_subdomain.push(c.to_ascii_lowercase());
                }
            }
            AddTunnelField::TunnelType => {
                // Space or enter toggles type
            }
        }
        self.add_tunnel_error = None;
    }

    pub fn form_backspace(&mut self) {
        match self.add_tunnel_field {
            AddTunnelField::Port => {
                self.add_tunnel_port.pop();
            }
            AddTunnelField::Subdomain => {
                self.add_tunnel_subdomain.pop();
            }
            AddTunnelField::TunnelType => {}
        }
        self.add_tunnel_error = None;
    }

    pub async fn form_submit(&mut self) {
        // Validate port
        let port: u16 = match self.add_tunnel_port.parse() {
            Ok(p) if p > 0 => p,
            _ => {
                self.add_tunnel_error = Some("Invalid port number".to_string());
                return;
            }
        };

        // Send command to connection
        let cmd = match self.add_tunnel_type {
            TunnelType::Http => {
                let subdomain = if self.add_tunnel_subdomain.is_empty() {
                    None
                } else {
                    Some(self.add_tunnel_subdomain.clone())
                };
                TuiCommand::AddHttpTunnel {
                    local_port: port,
                    subdomain,
                }
            }
            TunnelType::Tcp => TuiCommand::AddTcpTunnel { local_port: port },
        };

        if self.cmd_tx.send(cmd).await.is_err() {
            self.add_tunnel_error = Some("Failed to send command".to_string());
            return;
        }

        // Return to tunnel list
        self.view_mode = ViewMode::TunnelList;
    }

    fn handle_event(&mut self, event: TuiEvent) {
        match event {
            TuiEvent::TunnelRegistered(tunnel) => {
                self.tunnels.push(tunnel);
            }
            TuiEvent::TcpTunnelRegistered(tcp_tunnel) => {
                self.tcp_tunnels.push(tcp_tunnel);
            }
            TuiEvent::RequestReceived(req) => {
                let log = RequestLog {
                    id: req.request_id.clone(),
                    method: req.method,
                    path: req.path,
                    query_string: req.query_string,
                    request_headers: req.headers,
                    request_body: req.body,
                    status: None,
                    response_headers: Vec::new(),
                    response_body: None,
                    duration_ms: None,
                    timestamp: req.timestamp,
                    client_ip: req.client_ip,
                };

                // Insert at beginning (newest first)
                self.requests.insert(0, log);

                // Enforce max requests limit
                if self.requests.len() > self.max_requests {
                    self.requests.pop();
                }

                // Auto-select first item if nothing selected
                if self.table_state.selected().is_none() && !self.requests.is_empty() {
                    self.table_state.select(Some(0));
                } else if let Some(selected) = self.table_state.selected() {
                    // Keep selection on same item when new requests come in
                    if selected < self.requests.len() - 1 {
                        self.table_state.select(Some(selected + 1));
                    }
                }
            }
            TuiEvent::ResponseSent(resp) => {
                // Find the request and update it
                if let Some(req) = self.requests.iter_mut().find(|r| r.id == resp.request_id) {
                    req.status = Some(resp.status);
                    req.response_headers = resp.headers;
                    req.response_body = resp.body;
                    req.duration_ms = Some(resp.duration_ms);
                }
            }
            TuiEvent::ConnectionStatus(status) => {
                // Clear stale tunnel display when reconnecting (will repopulate when re-registered)
                if matches!(status, ConnectionStatus::Reconnecting { .. }) {
                    self.tunnels.clear();
                    self.tcp_tunnels.clear();
                }
                self.connection_status = status;
            }
        }
    }
}

pub struct Tui {
    terminal: Terminal<CrosstermBackend<io::Stdout>>,
    event_rx: mpsc::Receiver<TuiEvent>,
    cmd_tx: mpsc::Sender<TuiCommand>,
}

impl Tui {
    pub fn new(
        event_rx: mpsc::Receiver<TuiEvent>,
        cmd_tx: mpsc::Sender<TuiCommand>,
    ) -> Result<Self> {
        enable_raw_mode()?;
        let mut stdout = io::stdout();
        execute!(stdout, EnterAlternateScreen, EnableMouseCapture)?;
        let backend = CrosstermBackend::new(stdout);
        let terminal = Terminal::new(backend)?;

        Ok(Self {
            terminal,
            event_rx,
            cmd_tx,
        })
    }

    pub async fn run(&mut self) -> Result<()> {
        let mut app = App::new(self.cmd_tx.clone());

        loop {
            // Draw UI
            self.terminal.draw(|f| ui::draw(f, &mut app))?;

            // Poll keyboard with short timeout, then check for TUI events
            if event::poll(Duration::from_millis(10))? {
                if let Event::Key(key) = event::read()? {
                    if key.kind == KeyEventKind::Press {
                        handle_key(&mut app, key.code).await;
                    }
                }
            }

            // Process all pending TUI events without blocking
            while let Ok(event) = self.event_rx.try_recv() {
                app.handle_event(event);
            }

            if app.should_quit {
                break;
            }
        }

        Ok(())
    }
}

impl Drop for Tui {
    fn drop(&mut self) {
        let _ = disable_raw_mode();
        let _ = execute!(
            self.terminal.backend_mut(),
            LeaveAlternateScreen,
            DisableMouseCapture
        );
        let _ = self.terminal.show_cursor();
    }
}

async fn handle_key(app: &mut App, key: KeyCode) {
    match app.view_mode {
        ViewMode::TunnelList => match key {
            KeyCode::Char('q') => app.should_quit = true,
            KeyCode::Char('a') if app.is_connected() => app.enter_add_tunnel(),
            KeyCode::Char('j') | KeyCode::Down => app.tunnel_next(),
            KeyCode::Char('k') | KeyCode::Up => app.tunnel_previous(),
            KeyCode::Enter => app.view_tunnel_requests(),
            _ => {}
        },
        ViewMode::AddTunnel => match key {
            KeyCode::Esc => app.back(),
            KeyCode::Tab | KeyCode::Down => app.form_next_field(),
            KeyCode::BackTab | KeyCode::Up => app.form_prev_field(),
            KeyCode::Char(' ') if app.add_tunnel_field == AddTunnelField::TunnelType => {
                app.form_toggle_type()
            }
            KeyCode::Char(c) => app.form_input_char(c),
            KeyCode::Backspace => app.form_backspace(),
            KeyCode::Enter => app.form_submit().await,
            _ => {}
        },
        ViewMode::RequestList => match key {
            KeyCode::Char('q') => app.should_quit = true,
            KeyCode::Char('j') | KeyCode::Down => app.next(),
            KeyCode::Char('k') | KeyCode::Up => app.previous(),
            KeyCode::Char('g') => app.go_to_top(),
            KeyCode::Char('G') => app.go_to_bottom(),
            KeyCode::Char('c') => app.clear(),
            KeyCode::Enter => app.enter_request_detail(),
            KeyCode::Esc => app.back(),
            _ => {}
        },
        ViewMode::RequestDetail => match key {
            KeyCode::Char('q') => app.should_quit = true,
            KeyCode::Esc | KeyCode::Enter => app.back(),
            _ => {}
        },
    }
}

/// Creates a channel for sending events to the TUI
pub fn create_event_channel() -> (mpsc::Sender<TuiEvent>, mpsc::Receiver<TuiEvent>) {
    mpsc::channel(256)
}

/// Creates a channel for sending commands from TUI to connection
pub fn create_command_channel() -> (mpsc::Sender<TuiCommand>, mpsc::Receiver<TuiCommand>) {
    mpsc::channel(64)
}
