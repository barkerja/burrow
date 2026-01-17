use anyhow::Result;
use clap::Parser;
use tracing::info;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt, EnvFilter};

mod client;
mod crypto;
mod error;
mod protocol;

use client::tui::{create_event_channel, Tui};
use client::TunnelClient;

#[derive(Parser, Debug)]
#[command(name = "burrow")]
#[command(author, version, about = "Tunnel your local services to the internet")]
struct Args {
    /// Server hostname
    #[arg(short, long)]
    server: String,

    /// Local HTTP port to expose (can specify multiple)
    /// Format: PORT or PORT:SUBDOMAIN
    #[arg(short, long, required = true)]
    port: Vec<String>,

    /// Local TCP port to tunnel (can specify multiple)
    #[arg(short, long)]
    tcp: Vec<u16>,

    /// Local host to forward to
    #[arg(short = 'H', long, default_value = "localhost")]
    host: String,

    /// Requested subdomain (for single tunnel)
    #[arg(short = 'd', long)]
    subdomain: Option<String>,

    /// Path to keypair file
    #[arg(short, long)]
    keypair: Option<String>,

    /// Server port
    #[arg(long, default_value = "443")]
    server_port: u16,

    /// Enable verbose logging
    #[arg(short, long)]
    verbose: bool,

    /// Disable TUI and use plain text output
    #[arg(long)]
    no_tui: bool,
}

#[tokio::main]
async fn main() -> Result<()> {
    let args = Args::parse();

    // Parse port specifications early
    let tunnels = parse_port_specs(&args.port, args.subdomain.as_deref())?;

    // Create TUI channel if TUI is enabled
    let (tui_tx, tui_rx) = if args.no_tui {
        // Initialize logging for non-TUI mode
        let filter = if args.verbose {
            EnvFilter::new("debug")
        } else {
            EnvFilter::new("info")
        };

        tracing_subscriber::registry()
            .with(filter)
            .with(tracing_subscriber::fmt::layer())
            .init();

        info!("Starting Burrow tunnel client...");
        info!("Server: {}:{}", args.server, args.server_port);

        if tunnels.len() == 1 {
            let (port, _) = &tunnels[0];
            info!("Forwarding HTTP to: {}:{}", args.host, port);
        } else {
            info!("HTTP tunnels to start: {}", tunnels.len());
        }

        if !args.tcp.is_empty() {
            info!(
                "TCP tunnels to start: {} (ports: {:?})",
                args.tcp.len(),
                args.tcp
            );
        }

        (None, None)
    } else {
        // In TUI mode, only log errors to avoid interfering with display
        let filter = EnvFilter::new("error");
        tracing_subscriber::registry()
            .with(filter)
            .with(tracing_subscriber::fmt::layer())
            .init();

        let (tx, rx) = create_event_channel();
        (Some(tx), Some(rx))
    };

    // Create client
    let client = TunnelClient::new(
        &args.server,
        args.server_port,
        &args.host,
        tunnels,
        args.tcp,
        args.keypair,
        tui_tx,
    )?;

    if let Some(tui_rx) = tui_rx {
        // Run with TUI
        let mut tui = Tui::new(tui_rx)?;

        // Spawn client in background
        let client_handle = tokio::spawn(async move { client.run().await });

        // Run TUI (blocks until quit)
        let tui_result = tui.run().await;

        // Clean up
        client_handle.abort();

        tui_result
    } else {
        // Run without TUI
        client.run().await
    }
}

fn parse_port_specs(specs: &[String], default_subdomain: Option<&str>) -> Result<Vec<(u16, Option<String>)>> {
    let mut tunnels = Vec::new();

    for spec in specs {
        if let Some((port_str, subdomain)) = spec.split_once(':') {
            let port: u16 = port_str.parse()?;
            tunnels.push((port, Some(subdomain.to_string())));
        } else {
            let port: u16 = spec.parse()?;
            // Use default subdomain only if there's a single tunnel
            let subdomain = if specs.len() == 1 {
                default_subdomain.map(|s| s.to_string())
            } else {
                None
            };
            tunnels.push((port, subdomain));
        }
    }

    Ok(tunnels)
}
