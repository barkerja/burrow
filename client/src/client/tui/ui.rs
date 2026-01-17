use ratatui::{
    layout::{Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style, Stylize},
    text::{Line, Span},
    widgets::{Block, Borders, Cell, Paragraph, Row, Table, Wrap},
    Frame,
};

use super::{App, ViewMode};

pub fn draw(frame: &mut Frame, app: &mut App) {
    match app.view_mode {
        ViewMode::List => draw_list_view(frame, app),
        ViewMode::Detail => draw_detail_view(frame, app),
    }
}

fn draw_list_view(frame: &mut Frame, app: &mut App) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3), // Status bar
            Constraint::Min(5),    // Request list
            Constraint::Length(2), // Help footer
        ])
        .split(frame.area());

    draw_status_bar(frame, app, chunks[0]);
    draw_request_list(frame, app, chunks[1]);
    draw_help_footer(frame, app, chunks[2]);
}

fn draw_status_bar(frame: &mut Frame, app: &App, area: Rect) {
    let status_color = match app.connection_status {
        super::events::ConnectionStatus::Connected => Color::Green,
        super::events::ConnectionStatus::Connecting => Color::Yellow,
        super::events::ConnectionStatus::Reconnecting => Color::Yellow,
        super::events::ConnectionStatus::Disconnected => Color::Red,
    };

    let mut status_parts = vec![
        Span::styled(" burrow ", Style::default().fg(Color::Cyan).bold()),
        Span::raw("│ "),
        Span::styled(
            format!("{}", app.connection_status),
            Style::default().fg(status_color).bold(),
        ),
    ];

    // Show tunnel URLs
    for tunnel in &app.tunnels {
        status_parts.push(Span::raw(" │ "));
        status_parts.push(Span::styled(
            format!("{} → :{}", tunnel.full_url, tunnel.local_port),
            Style::default().fg(Color::Green),
        ));
    }

    for tcp in &app.tcp_tunnels {
        status_parts.push(Span::raw(" │ "));
        status_parts.push(Span::styled(
            format!("tcp:{} → :{}", tcp.server_port, tcp.local_port),
            Style::default().fg(Color::Magenta),
        ));
    }

    status_parts.push(Span::raw(" │ "));
    status_parts.push(Span::styled(
        format!("Reqs: {}", app.requests.len()),
        Style::default().fg(Color::White),
    ));

    let status_line = Line::from(status_parts);
    let status = Paragraph::new(status_line)
        .block(Block::default().borders(Borders::ALL).title(" Status "));

    frame.render_widget(status, area);
}

fn draw_request_list(frame: &mut Frame, app: &mut App, area: Rect) {
    let header_cells = ["METHOD", "PATH", "STATUS", "TIME"]
        .iter()
        .map(|h| Cell::from(*h).style(Style::default().fg(Color::Yellow).bold()));
    let header = Row::new(header_cells).height(1).bottom_margin(1);

    let rows = app.requests.iter().map(|req| {
        let method_style = method_color(&req.method);
        let status_style = status_color(req.status);
        let duration = req
            .duration_ms
            .map(|d| format!("{}ms", d))
            .unwrap_or_else(|| "...".to_string());

        Row::new(vec![
            Cell::from(req.method.clone()).style(method_style),
            Cell::from(truncate_path(&req.path, 40)),
            Cell::from(
                req.status
                    .map(|s| s.to_string())
                    .unwrap_or_else(|| "...".to_string()),
            )
            .style(status_style),
            Cell::from(duration),
        ])
    });

    let widths = [
        Constraint::Length(8),
        Constraint::Min(20),
        Constraint::Length(8),
        Constraint::Length(10),
    ];

    let table = Table::new(rows, widths)
        .header(header)
        .block(Block::default().borders(Borders::ALL).title(" Requests "))
        .row_highlight_style(Style::default().add_modifier(Modifier::REVERSED))
        .highlight_symbol("► ");

    frame.render_stateful_widget(table, area, &mut app.table_state);
}

fn draw_help_footer(frame: &mut Frame, _app: &App, area: Rect) {
    let help_text = Line::from(vec![
        Span::styled(" j/↓ ", Style::default().fg(Color::Yellow)),
        Span::raw("Down "),
        Span::styled(" k/↑ ", Style::default().fg(Color::Yellow)),
        Span::raw("Up "),
        Span::styled(" Enter ", Style::default().fg(Color::Yellow)),
        Span::raw("Details "),
        Span::styled(" c ", Style::default().fg(Color::Yellow)),
        Span::raw("Clear "),
        Span::styled(" q ", Style::default().fg(Color::Yellow)),
        Span::raw("Quit"),
    ]);

    let help = Paragraph::new(help_text)
        .block(Block::default().borders(Borders::TOP));

    frame.render_widget(help, area);
}

fn draw_detail_view(frame: &mut Frame, app: &App) {
    let Some(selected) = app.table_state.selected() else {
        return draw_list_view(frame, &mut app.clone());
    };

    let Some(req) = app.requests.get(selected) else {
        return;
    };

    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3), // Title bar
            Constraint::Min(5),    // Content
            Constraint::Length(2), // Help footer
        ])
        .split(frame.area());

    // Title bar
    let status_text = req
        .status
        .map(|s| format!("{} {}", s, status_text(s)))
        .unwrap_or_else(|| "Pending...".to_string());

    let full_path = if req.query_string.is_empty() {
        req.path.clone()
    } else {
        format!("{}?{}", req.path, req.query_string)
    };

    let title = Line::from(vec![
        Span::styled(
            format!(" {} ", req.method),
            method_color(&req.method).bold(),
        ),
        Span::raw(truncate_string(&full_path, 60)),
        Span::raw(" │ "),
        Span::styled(status_text, status_color(req.status)),
    ]);

    let title_bar = Paragraph::new(title)
        .block(Block::default().borders(Borders::ALL).title(" Request Detail "));
    frame.render_widget(title_bar, chunks[0]);

    // Content area split into sections
    let has_request_body = req.request_body.as_ref().map(|b| !b.is_empty()).unwrap_or(false);
    let content_chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints(if has_request_body {
            vec![
                Constraint::Length(5),  // Summary info
                Constraint::Length(5),  // Request headers
                Constraint::Length(5),  // Request body
                Constraint::Length(5),  // Response headers
                Constraint::Min(3),     // Response body
            ]
        } else {
            vec![
                Constraint::Length(5),  // Summary info
                Constraint::Length(6),  // Request headers
                Constraint::Length(6),  // Response headers
                Constraint::Min(3),     // Response body
            ]
        })
        .split(chunks[1]);

    // Summary section with key details
    let user_agent = get_header_value(&req.request_headers, "user-agent")
        .unwrap_or("-".to_string());
    let client_ip = req.client_ip.as_deref().unwrap_or("-");
    let duration = req
        .duration_ms
        .map(|d| format!("{}ms", d))
        .unwrap_or_else(|| "...".to_string());
    let timestamp = req.timestamp.format("%H:%M:%S").to_string();

    let summary_lines = vec![
        Line::from(vec![
            Span::styled("  Client IP: ", Style::default().fg(Color::Yellow)),
            Span::raw(client_ip),
            Span::raw("    "),
            Span::styled("Time: ", Style::default().fg(Color::Yellow)),
            Span::raw(&timestamp),
            Span::raw("    "),
            Span::styled("Duration: ", Style::default().fg(Color::Yellow)),
            Span::raw(&duration),
        ]),
        Line::from(vec![
            Span::styled("  User-Agent: ", Style::default().fg(Color::Yellow)),
            Span::raw(truncate_string(&user_agent, 80)),
        ]),
    ];

    let summary = Paragraph::new(summary_lines)
        .block(Block::default().borders(Borders::ALL).title(" Summary "));
    frame.render_widget(summary, content_chunks[0]);

    // Request headers
    let req_headers_text = format_headers(&req.request_headers);
    let req_headers = Paragraph::new(req_headers_text)
        .block(Block::default().borders(Borders::ALL).title(" Request Headers "))
        .wrap(Wrap { trim: false });
    frame.render_widget(req_headers, content_chunks[1]);

    // Dynamic indices based on whether request body exists
    let (resp_headers_idx, resp_body_idx) = if has_request_body {
        // Request body section
        let req_body_text = req
            .request_body
            .as_ref()
            .map(|b| format_body(b))
            .unwrap_or_else(|| "No body".to_string());
        let req_body = Paragraph::new(req_body_text)
            .block(Block::default().borders(Borders::ALL).title(" Request Body "))
            .wrap(Wrap { trim: false });
        frame.render_widget(req_body, content_chunks[2]);
        (3, 4)
    } else {
        (2, 3)
    };

    // Response headers
    let resp_headers_text = format_headers(&req.response_headers);
    let resp_headers = Paragraph::new(resp_headers_text)
        .block(Block::default().borders(Borders::ALL).title(" Response Headers "))
        .wrap(Wrap { trim: false });
    frame.render_widget(resp_headers, content_chunks[resp_headers_idx]);

    // Response body
    let body_text = req
        .response_body
        .as_ref()
        .map(|b| format_body(b))
        .unwrap_or_else(|| "No body".to_string());
    let body = Paragraph::new(body_text)
        .block(Block::default().borders(Borders::ALL).title(" Response Body "))
        .wrap(Wrap { trim: false });
    frame.render_widget(body, content_chunks[resp_body_idx]);

    // Help footer
    let help_text = Line::from(vec![
        Span::styled(" Esc ", Style::default().fg(Color::Yellow)),
        Span::raw("Back "),
        Span::styled(" q ", Style::default().fg(Color::Yellow)),
        Span::raw("Quit"),
    ]);

    let help = Paragraph::new(help_text)
        .block(Block::default().borders(Borders::TOP));
    frame.render_widget(help, chunks[2]);
}

fn method_color(method: &str) -> Style {
    match method {
        "GET" => Style::default().fg(Color::Green),
        "POST" => Style::default().fg(Color::Blue),
        "PUT" => Style::default().fg(Color::Yellow),
        "PATCH" => Style::default().fg(Color::Yellow),
        "DELETE" => Style::default().fg(Color::Red),
        _ => Style::default().fg(Color::White),
    }
}

fn status_color(status: Option<u16>) -> Style {
    match status {
        Some(s) if s >= 200 && s < 300 => Style::default().fg(Color::Green),
        Some(s) if s >= 300 && s < 400 => Style::default().fg(Color::Cyan),
        Some(s) if s >= 400 && s < 500 => Style::default().fg(Color::Yellow),
        Some(s) if s >= 500 => Style::default().fg(Color::Red),
        _ => Style::default().fg(Color::Gray),
    }
}

fn status_text(status: u16) -> &'static str {
    match status {
        200 => "OK",
        201 => "Created",
        204 => "No Content",
        301 => "Moved Permanently",
        302 => "Found",
        304 => "Not Modified",
        400 => "Bad Request",
        401 => "Unauthorized",
        403 => "Forbidden",
        404 => "Not Found",
        405 => "Method Not Allowed",
        422 => "Unprocessable Entity",
        429 => "Too Many Requests",
        500 => "Internal Server Error",
        502 => "Bad Gateway",
        503 => "Service Unavailable",
        504 => "Gateway Timeout",
        _ => "",
    }
}

fn truncate_path(path: &str, max_len: usize) -> String {
    if path.len() <= max_len {
        path.to_string()
    } else {
        format!("{}...", &path[..max_len - 3])
    }
}

fn format_headers(headers: &[(String, String)]) -> String {
    if headers.is_empty() {
        return "  (none)".to_string();
    }
    headers
        .iter()
        .map(|(k, v)| {
            let display_value = if k.to_lowercase() == "authorization" {
                "***".to_string()
            } else if v.len() > 60 {
                format!("{}...", &v[..57])
            } else {
                v.clone()
            };
            format!("  {}: {}", k, display_value)
        })
        .collect::<Vec<_>>()
        .join("\n")
}

fn format_body(body: &[u8]) -> String {
    match String::from_utf8(body.to_vec()) {
        Ok(s) => {
            // Try to pretty-print JSON
            if let Ok(json) = serde_json::from_str::<serde_json::Value>(&s) {
                serde_json::to_string_pretty(&json).unwrap_or(s)
            } else {
                s
            }
        }
        Err(_) => format!("[Binary data: {} bytes]", body.len()),
    }
}

fn get_header_value(headers: &[(String, String)], name: &str) -> Option<String> {
    headers
        .iter()
        .find(|(k, _)| k.to_lowercase() == name.to_lowercase())
        .map(|(_, v)| v.clone())
}

fn truncate_string(s: &str, max_len: usize) -> String {
    if s.len() <= max_len {
        s.to_string()
    } else {
        format!("{}...", &s[..max_len - 3])
    }
}
