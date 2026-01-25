//! Burrow Tunnel Client
//!
//! A CLI tool for exposing local services via secure tunnels.
//!
//! This client connects to a Burrow server and establishes tunnels for:
//! - HTTP/HTTPS traffic (with subdomain-based routing)
//! - WebSocket connections
//! - Raw TCP connections
//!
//! The client authenticates using API tokens obtained from the Burrow web UI.

#![deny(clippy::correctness)]
#![warn(clippy::suspicious)]
#![warn(clippy::style)]
#![warn(clippy::complexity)]
#![warn(clippy::perf)]

use anyhow::{Context, Result};
use clap::{Parser, Subcommand};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt, EnvFilter};

mod client;
mod config;
mod crypto;
mod error;
mod protocol;

use client::tui::{create_event_channel, Tui};
use client::TunnelClient;
use config::Config;

#[derive(Parser, Debug)]
#[command(name = "burrow")]
#[command(author, version, about = "Tunnel your local services to the internet")]
struct Cli {
    #[command(subcommand)]
    command: Option<Commands>,

    /// Server hostname
    #[arg(short, long, global = true, env = "BURROW_SERVER")]
    server: Option<String>,

    /// API token for authentication (from Burrow web UI)
    #[arg(short = 'k', long, global = true, env = "BURROW_TOKEN")]
    token: Option<String>,

    /// Enable verbose logging
    #[arg(short, long, global = true)]
    verbose: bool,
}

#[derive(Subcommand, Debug)]
enum Commands {
    /// Start a tunnel to expose local services
    Start(StartArgs),

    /// Authenticate and save your API token
    Login,

    /// Manage your subdomain reservations
    Subdomains {
        #[command(subcommand)]
        action: Option<SubdomainCommands>,
    },
}

#[derive(Parser, Debug)]
struct StartArgs {
    /// Local host to forward to
    #[arg(short = 'H', long, default_value = "localhost")]
    host: String,

    /// Server port
    #[arg(long, default_value = "443")]
    server_port: u16,

    /// Disable TUI and use plain text output
    #[arg(long)]
    no_tui: bool,
}

#[derive(Subcommand, Debug)]
enum SubdomainCommands {
    /// Release a subdomain reservation
    Release {
        /// The subdomain to release
        subdomain: String,
    },
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();
    let config = Config::load().unwrap_or_default();

    // Resolve server from CLI > config > error
    let server = cli
        .server
        .or(config.auth.server.clone())
        .unwrap_or_else(|| "localhost".to_string());

    match cli.command {
        Some(Commands::Start(args)) => {
            run_start(cli.token, cli.verbose, &server, args, &config).await
        }
        Some(Commands::Login) => run_login(&server).await,
        Some(Commands::Subdomains { action }) => {
            run_subdomains(cli.token, &server, action, &config).await
        }
        None => {
            // If no subcommand, show help
            eprintln!("No command specified. Use --help for usage information.");
            eprintln!();
            eprintln!("Quick start:");
            eprintln!(
                "  burrow start -s <server>              Start the TUI and configure tunnels"
            );
            eprintln!("  burrow login -s <server>              Authenticate");
            eprintln!("  burrow subdomains -s <server>         List your subdomains");
            std::process::exit(1);
        }
    }
}

async fn run_start(
    cli_token: Option<String>,
    _verbose: bool,
    server: &str,
    args: StartArgs,
    config: &Config,
) -> Result<()> {
    if args.no_tui {
        anyhow::bail!("--no-tui mode requires tunnels to be configured via CLI flags, which have been removed. Use TUI mode instead.");
    }

    // In TUI mode, only log errors
    let filter = EnvFilter::new("error");
    tracing_subscriber::registry()
        .with(filter)
        .with(tracing_subscriber::fmt::layer())
        .init();

    let (tui_tx, tui_rx) = create_event_channel();

    let token = cli_token.or(config.auth.token.clone()).ok_or_else(|| {
        anyhow::anyhow!(
            "API token required. Use --token, set BURROW_TOKEN environment variable, \n\
             or add token to config file at {:?}.\n\
             Get a token from the Burrow web UI at https://{}/account",
            Config::config_path().unwrap_or_default(),
            server
        )
    })?;

    let (cmd_tx, cmd_rx) = client::tui::create_command_channel();

    let client = TunnelClient::new(
        server,
        args.server_port,
        &args.host,
        token,
        Some(tui_tx),
        cmd_rx,
    )?;

    let mut tui = Tui::new(tui_rx, cmd_tx)?;
    let client_handle = tokio::spawn(async move { client.run().await });
    let tui_result = tui.run().await;
    client_handle.abort();
    tui_result
}

async fn run_login(server: &str) -> Result<()> {
    let account_url = format!("https://{}/account", server);

    println!("To authenticate, visit the following URL in your browser:");
    println!();
    println!("  {}", account_url);
    println!();
    println!("Create an API token there and paste it below.");
    println!();

    // Try to open browser
    if open::that(&account_url).is_err() {
        println!("(Could not open browser automatically)");
        println!();
    }

    print!("API Token: ");
    use std::io::{self, Write};
    io::stdout().flush()?;

    let mut token = String::new();
    io::stdin().read_line(&mut token)?;
    let token = token.trim().to_string();

    if token.is_empty() {
        anyhow::bail!("No token provided");
    }

    if !token.starts_with("brw_") {
        anyhow::bail!("Invalid token format. Tokens should start with 'brw_'");
    }

    // Save to config
    let mut config = Config::load().unwrap_or_default();
    config.auth.token = Some(token);
    config.auth.server = Some(server.to_string());
    config.save()?;

    println!();
    println!(
        "Token saved to {:?}",
        Config::config_path().unwrap_or_default()
    );
    println!("You can now run: burrow start -p <port>");

    Ok(())
}

async fn run_subdomains(
    cli_token: Option<String>,
    server: &str,
    action: Option<SubdomainCommands>,
    config: &Config,
) -> Result<()> {
    init_logging(false);

    let token = cli_token.or(config.auth.token.clone()).ok_or_else(|| {
        anyhow::anyhow!("API token required. Run 'burrow login' first or use --token")
    })?;

    let client = reqwest::Client::new();
    let base_url = format!("https://{}", server);

    match action {
        Some(SubdomainCommands::Release { subdomain }) => {
            let resp = client
                .delete(format!("{}/api/subdomains/{}", base_url, subdomain))
                .bearer_auth(&token)
                .send()
                .await
                .context("Failed to contact server")?;

            if resp.status().is_success() {
                println!("Subdomain '{}' released", subdomain);
            } else {
                let status = resp.status();
                let body: serde_json::Value = resp.json().await.unwrap_or_default();
                let msg = body["error"]["message"].as_str().unwrap_or("Unknown error");
                anyhow::bail!("Failed to release subdomain: {} - {}", status, msg);
            }
        }
        None => {
            let resp = client
                .get(format!("{}/api/subdomains", base_url))
                .bearer_auth(&token)
                .send()
                .await
                .context("Failed to contact server")?;

            if resp.status().is_success() {
                let body: serde_json::Value = resp.json().await?;
                let subdomains = body["subdomains"].as_array();

                match subdomains {
                    Some(list) if !list.is_empty() => {
                        println!("Your reserved subdomains:");
                        println!();
                        for sub in list {
                            let name = sub["subdomain"].as_str().unwrap_or("?");
                            let created = sub["created_at"].as_str().unwrap_or("?");
                            println!("  {} (reserved {})", name, created);
                        }
                        println!();
                        println!("To release a subdomain: burrow subdomains release <name>");
                    }
                    _ => {
                        println!("No subdomains reserved yet.");
                        println!("Subdomains are automatically reserved when you start a tunnel.");
                    }
                }
            } else {
                let status = resp.status();
                let body: serde_json::Value = resp.json().await.unwrap_or_default();
                let msg = body["error"]["message"].as_str().unwrap_or("Unknown error");
                anyhow::bail!("Failed to list subdomains: {} - {}", status, msg);
            }
        }
    }

    Ok(())
}

fn init_logging(verbose: bool) {
    let filter = if verbose {
        EnvFilter::new("debug")
    } else {
        EnvFilter::new("info")
    };

    let _ = tracing_subscriber::registry()
        .with(filter)
        .with(tracing_subscriber::fmt::layer())
        .try_init();
}
