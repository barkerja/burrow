mod events;
mod ui;

pub use events::*;

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
    pub id: String,
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
    List,
    Detail,
}

/// TUI application state
#[derive(Clone)]
pub struct App {
    pub tunnels: Vec<TunnelEvent>,
    pub tcp_tunnels: Vec<TcpTunnelEvent>,
    pub requests: Vec<RequestLog>,
    pub table_state: TableState,
    pub view_mode: ViewMode,
    pub connection_status: ConnectionStatus,
    pub should_quit: bool,
    max_requests: usize,
}

impl App {
    pub fn new() -> Self {
        Self {
            tunnels: Vec::new(),
            tcp_tunnels: Vec::new(),
            requests: Vec::new(),
            table_state: TableState::default(),
            view_mode: ViewMode::List,
            connection_status: ConnectionStatus::Connecting,
            should_quit: false,
            max_requests: 1000,
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

    pub fn toggle_detail(&mut self) {
        if self.table_state.selected().is_some() {
            self.view_mode = match self.view_mode {
                ViewMode::List => ViewMode::Detail,
                ViewMode::Detail => ViewMode::List,
            };
        }
    }

    pub fn back(&mut self) {
        self.view_mode = ViewMode::List;
    }

    pub fn clear(&mut self) {
        self.requests.clear();
        self.table_state.select(None);
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
                self.connection_status = status;
            }
            TuiEvent::Shutdown => {
                self.should_quit = true;
            }
        }
    }
}

pub struct Tui {
    terminal: Terminal<CrosstermBackend<io::Stdout>>,
    event_rx: mpsc::Receiver<TuiEvent>,
}

impl Tui {
    pub fn new(event_rx: mpsc::Receiver<TuiEvent>) -> Result<Self> {
        enable_raw_mode()?;
        let mut stdout = io::stdout();
        execute!(stdout, EnterAlternateScreen, EnableMouseCapture)?;
        let backend = CrosstermBackend::new(stdout);
        let terminal = Terminal::new(backend)?;

        Ok(Self { terminal, event_rx })
    }

    pub async fn run(&mut self) -> Result<()> {
        let mut app = App::new();

        loop {
            // Draw UI
            self.terminal.draw(|f| ui::draw(f, &mut app))?;

            // Poll keyboard with short timeout, then check for TUI events
            if event::poll(Duration::from_millis(10))? {
                if let Event::Key(key) = event::read()? {
                    if key.kind == KeyEventKind::Press {
                        handle_key(&mut app, key.code);
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

fn handle_key(app: &mut App, key: KeyCode) {
    match app.view_mode {
        ViewMode::List => match key {
            KeyCode::Char('q') => app.should_quit = true,
            KeyCode::Char('j') | KeyCode::Down => app.next(),
            KeyCode::Char('k') | KeyCode::Up => app.previous(),
            KeyCode::Char('g') => app.go_to_top(),
            KeyCode::Char('G') => app.go_to_bottom(),
            KeyCode::Char('c') => app.clear(),
            KeyCode::Enter => app.toggle_detail(),
            _ => {}
        },
        ViewMode::Detail => match key {
            KeyCode::Char('q') => app.should_quit = true,
            KeyCode::Esc => app.back(),
            KeyCode::Enter => app.back(),
            _ => {}
        },
    }
}

/// Creates a channel for sending events to the TUI
pub fn create_event_channel() -> (mpsc::Sender<TuiEvent>, mpsc::Receiver<TuiEvent>) {
    mpsc::channel(256)
}
