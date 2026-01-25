<p align="center">
    <picture>
      <img src="./priv/static/images/burrow_tunnel_logo.png" alt="Burrow logo" />
    </picture>
</p>

# Burrow

A lightweight ngrok clone. Expose local services to the internet through secure tunnels with subdomain-based routing.

## Overview

Burrow enables developers to expose local web services to the internet through a public server. It consists of two components:

- **Server**: An Elixir-based public-facing server that accepts incoming requests and routes them through WebSocket tunnels to connected clients
- **Client**: A Rust CLI tool that establishes tunnels to the server and forwards requests to local services

Key features:
- Subdomain-based routing (e.g., `myapp.tunnel.example.com`)
- WebSocket-based bidirectional tunnel communication
- WebAuthn passkey authentication (passwordless)
- API token-based client authentication
- Subdomain reservations for consistent URLs
- Built-in TLS with automatic Let's Encrypt certificate management
- DNS-01 challenge support for wildcard certificates (Cloudflare)
- TCP tunneling for databases, Redis, etc.
- Web-based request inspector with filtering
- Interactive TUI for tunnel management

## Quick Start

### Install the Client

#### From Releases (Recommended)

Download the latest binary for your platform from the [releases page](https://github.com/barkerja/burrow/releases):

| Platform | Download |
|----------|----------|
| Linux x86_64 | `burrow-vX.X.X-x86_64-unknown-linux-gnu.tar.gz` |
| Linux ARM64 | `burrow-vX.X.X-aarch64-unknown-linux-gnu.tar.gz` |
| macOS ARM64 (Apple Silicon) | `burrow-vX.X.X-aarch64-apple-darwin.tar.gz` |
| Windows x86_64 | `burrow-vX.X.X-x86_64-pc-windows-msvc.zip` |
| Windows ARM64 | `burrow-vX.X.X-aarch64-pc-windows-msvc.zip` |

```bash
# Example: Linux x86_64
curl -LO https://github.com/barkerja/burrow/releases/latest/download/burrow-vX.X.X-x86_64-unknown-linux-gnu.tar.gz
tar -xzf burrow-*.tar.gz
sudo mv burrow-*/burrow /usr/local/bin/
```

#### From Source (Rust)

```bash
git clone https://github.com/barkerja/burrow.git
cd burrow/client
cargo build --release
sudo cp target/release/burrow /usr/local/bin/
```

### Authenticate

Before using Burrow, you need to authenticate and get an API token:

```bash
burrow login -s tunnel.example.com
```

This will:
1. Open your browser to the Burrow web UI
2. Prompt you to register/login with a passkey
3. Ask you to create an API token
4. Save the token to `~/.config/burrow/config.toml`

### Start Tunnels

```bash
# Start the TUI and configure tunnels interactively
burrow start -s tunnel.example.com
```

The TUI allows you to:
- View active tunnels
- Add new HTTP or TCP tunnels
- Monitor requests in real-time
- View request/response details

### CLI Reference

```
USAGE:
    burrow <COMMAND>

COMMANDS:
    start       Start the tunnel client (TUI mode)
    login       Authenticate and save your API token
    subdomains  Manage your subdomain reservations
    help        Print help information

GLOBAL OPTIONS:
    -s, --server <HOST>     Server hostname (or set BURROW_SERVER)
    -k, --token <TOKEN>     API token (or set BURROW_TOKEN)
    -v, --verbose           Enable verbose logging
    -h, --help              Print help
    -V, --version           Print version
```

### Configuration

The client stores configuration in `~/.config/burrow/config.toml`:

```toml
[auth]
token = "your-api-token"
server = "tunnel.example.com"
```

You can also use environment variables:
- `BURROW_SERVER` - Server hostname
- `BURROW_TOKEN` - API token

## TUI Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `Tab` | Switch between tunnel list and request list |
| `a` | Add new tunnel (from tunnel list) |
| `Enter` | View request details / Submit form |
| `Esc` | Go back / Cancel |
| `q` | Quit |
| `↑/↓` | Navigate lists |

## Authentication

Burrow uses a two-layer authentication system:

### Web UI: WebAuthn Passkeys

The web interface uses passwordless authentication via WebAuthn:

1. **Register**: Create an account with just a username and your device's passkey (fingerprint, Face ID, security key, etc.)
2. **Login**: Authenticate using your passkey - no passwords to remember

### Client: API Tokens

The CLI client authenticates using API tokens:

1. Create a token in the web UI at `/account`
2. Run `burrow login` to save it locally
3. Tokens can be revoked anytime from the web UI

This means:
- **No passwords anywhere** - passkeys for web, tokens for CLI
- **Revocable access** - disable a token without changing your account
- **Multiple devices** - create separate tokens for each machine

## Subdomain Reservations

Reserve subdomains to get consistent URLs:

1. Go to the web UI at `/account`
2. Reserve a subdomain (e.g., `myapp`)
3. Use it in your tunnels

Reserved subdomains are tied to your account and can't be used by others.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│ Internet                                                            │
│   User requests https://myapp.tunnel.example.com/api/users          │
└─────────────────────────────┬───────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│ Burrow Server (Elixir)                                              │
│  ┌─────────────────┐     ┌──────────────────┐     ┌──────────────┐  │
│  │ Bandit (HTTPS)  │────▶│ Dispatcher       │────▶│TunnelRegistry│  │
│  │ + ACME/TLS      │     │                  │     │              │  │
│  └─────────────────┘     └──────────────────┘     └──────┬───────┘  │
│                                                          │          │
│  ┌─────────────────┐     ┌──────────────────┐            │          │
│  │ PostgreSQL      │◀───│ RequestStore     │            │          │
│  │ (requests, etc) │     │ (logging)        │            │          │
│  └─────────────────┘     └──────────────────┘            │          │
└──────────────────────────────────────────────────────────┼──────────┘
                                                           │ WebSocket
                                                           ▼
┌─────────────────────────────────────────────────────────────────────┐
│ Burrow Client (Rust)                                                │
│  ┌─────────────────┐     ┌──────────────────┐     ┌──────────────┐  │
│  │ Connection      │◀───▶│ LocalForwarder   │────▶│ Local Service│  │
│  │ (WebSocket)     │     │ (HTTP Client)    │     │ (port 3000)  │  │
│  └─────────────────┘     └──────────────────┘     └──────────────┘  │
│                                                                     │
│  ┌─────────────────┐                                                │
│  │ TUI (ratatui)   │  Interactive tunnel management                 │
│  └─────────────────┘                                                │
└─────────────────────────────────────────────────────────────────────┘
```

## Running Your Own Server

### Prerequisites

- Elixir 1.19+ / OTP 28+
- PostgreSQL 14+
- A domain with DNS you control (for wildcard certs)

### Quick Server Start (Development)

```bash
cd burrow

# Install dependencies
mix deps.get

# Setup database
mix ecto.create
mix ecto.migrate

# Start server
DATABASE_URL=ecto://user:pass@localhost/burrow BURROW_MODE=server mix run --no-halt
```

### Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `DATABASE_URL` | Yes | PostgreSQL connection URL |
| `BURROW_MODE` | Yes | Set to `server` |
| `PORT` / `BURROW_PORT` | No | Server port (default: 4000) |
| `BASE_DOMAIN` / `BURROW_DOMAIN` | No | Base domain for tunnels |
| `SECRET_KEY_BASE` | Prod | Phoenix secret key |
| `ACME_EMAIL` | Prod | Let's Encrypt contact email |
| `ACME_DOMAINS` | Prod | Domains for certificates |
| `CLOUDFLARE_API_TOKEN` | Prod | For DNS-01 challenges |
| `CLOUDFLARE_ZONE_ID` | Prod | Cloudflare zone ID |

### Production Deployment

See [docs/CLOUD_DEPLOYMENT.md](docs/CLOUD_DEPLOYMENT.md) for deploying to:

- **Fly.io** - Global edge deployment with dedicated IPs (recommended)

## Project Structure

```
burrow/
├── client/                 # Rust CLI client
│   ├── src/
│   │   ├── main.rs         # CLI entry point
│   │   ├── config.rs       # Token/config management
│   │   ├── client/         # Connection and TUI
│   │   └── protocol/       # Message types and IDs
│   └── Cargo.toml
├── lib/burrow/             # Elixir server
│   ├── accounts.ex         # User account context
│   ├── webauthn.ex         # WebAuthn authentication
│   ├── repo.ex             # Ecto repository
│   ├── schemas/            # Database schemas
│   ├── queries/            # Query modules
│   ├── workers/            # Oban background jobs
│   ├── server/             # Server components
│   │   ├── supervisor.ex
│   │   ├── dispatcher.ex
│   │   ├── tunnel_socket.ex
│   │   ├── tunnel_registry.ex
│   │   ├── request_store.ex
│   │   └── web/            # Phoenix LiveView UI
│   ├── protocol/           # Tunnel protocol
│   └── acme/               # Let's Encrypt integration
├── priv/
│   ├── repo/migrations/    # Database migrations
│   └── static/             # Static assets
└── config/                 # Server configuration
```

## Development

### Server (Elixir)

```bash
# Install dependencies
mix deps.get

# Setup database
mix ecto.setup

# Run tests
mix test

# Format code
mix format

# Start development server
DATABASE_URL=ecto://localhost/burrow_dev BURROW_MODE=server mix run --no-halt
```

### Client (Rust)

```bash
cd client

# Build
cargo build

# Build release
cargo build --release

# Run tests
cargo test

# Format
cargo fmt

# Lint
cargo clippy
```

## Tech Stack

**Server:**
- Elixir 1.19+ with OTP 28+
- PostgreSQL - Request storage, user accounts
- Bandit - Pure Elixir HTTP server with TLS
- Phoenix LiveView - Request inspector UI
- Oban - Background job processing
- Wax - WebAuthn authentication

**Client:**
- Rust
- tokio - Async runtime
- tungstenite - WebSocket client
- ratatui - Terminal UI
- clap - CLI argument parsing

## License

MIT
