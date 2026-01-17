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
- Ed25519 attestation-based authentication
- Persistent keypairs for consistent subdomains
- Built-in TLS with automatic Let's Encrypt certificate management
- DNS-01 challenge support for wildcard certificates (Cloudflare)
- TCP tunneling for databases, Redis, etc.
- Web-based request inspector

## Quick Start

### Install the Client

#### From Source (Rust)

```bash
git clone https://github.com/barkerja/burrow.git
cd burrow/client
cargo build --release

# Binary is at target/release/burrow
cp target/release/burrow /usr/local/bin/
```

### Expose a Local Service

```bash
# Expose port 3000 through a public server
burrow -s tunnel.example.com -p 3000

# Output:
# === Tunnel Active ===
#   Public URL: https://abc123.tunnel.example.com
#   Forwarding to: localhost:3000
```

### CLI Options

```
USAGE:
    burrow --server <HOST> --port <PORT> [OPTIONS]

REQUIRED:
    -s, --server <HOST>     Server hostname
    -p, --port <PORT>       Local HTTP port to expose (can specify multiple)
                            Format: PORT or PORT:SUBDOMAIN

OPTIONS:
    -t, --tcp <PORT>        Local TCP port to tunnel (can specify multiple)
    -h, --host <HOST>       Local host (default: localhost)
    -d, --subdomain <NAME>  Requested subdomain (for single tunnel)
    -k, --keypair <PATH>    Path to keypair file (default: ~/.burrow/keypair.json)
        --server-port <PORT> Server port (default: 443)
        --help              Show help
```

### Persistent Subdomain

Use a keypair file to get the same subdomain every time:

```bash
# First run - generates keypair and subdomain
burrow -s tunnel.example.com -p 3000
# => https://a1b2c3.tunnel.example.com

# Future runs - same subdomain (keypair stored in ~/.burrow/keypair.json)
burrow -s tunnel.example.com -p 3000
# => https://a1b2c3.tunnel.example.com
```

### Multiple Tunnels

Expose multiple ports in a single command:

```bash
# Multiple HTTP ports with custom subdomains
burrow -s tunnel.example.com -p 3000 -p 4000:api -p 5173:vite

# Output:
# === Tunnels Active ===
# HTTP:
#   https://abc123.tunnel.example.com -> localhost:3000
#   https://api.tunnel.example.com -> localhost:4000
#   https://vite.tunnel.example.com -> localhost:5173
```

### TCP Tunneling

Tunnel raw TCP connections for databases, Redis, etc.:

```bash
# HTTP + TCP tunnel for PostgreSQL
burrow -s tunnel.example.com -p 3000 --tcp 5432

# Output:
# === Tunnels Active ===
# HTTP:
#   https://abc123.tunnel.example.com -> localhost:3000
# TCP:
#   tunnel.example.com:40000 -> localhost:5432

# Connect from anywhere:
psql -h tunnel.example.com -p 40000 -U myuser mydb
```

## Security & Authentication

Burrow uses **Ed25519 digital signatures** for authentication:

1. Client generates or loads an Ed25519 keypair
2. Client signs a timestamped message (attestation)
3. Server verifies the signature and timestamp
4. Subdomain is derived from the public key hash

This means:
- **No passwords or API keys** - just your keypair
- **Same keypair = same subdomain** - deterministic assignment
- **Cryptographically secure** - can't impersonate other clients

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│ Internet                                                            │
│   User requests https://myapp.tunnel.example.com/api/users          │
└─────────────────────────────────┬───────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│ Burrow Server (Elixir)                                              │
│  ┌─────────────────┐     ┌──────────────────┐     ┌──────────────┐  │
│  │ Bandit (HTTPS)  │───▶│ Dispatcher       │───▶│TunnelRegistry│  │
│  │ + ACME/TLS      │     │                  │     │              │  │
│  └─────────────────┘     └──────────────────┘     └──────┬───────┘  │
└──────────────────────────────────────────────────────────┼──────────┘
                                                           │ WebSocket
                                                           ▼
┌─────────────────────────────────────────────────────────────────────┐
│ Burrow Client (Rust)                                                │
│  ┌─────────────────┐     ┌──────────────────┐     ┌──────────────┐  │
│  │ Connection      │◀─▶│ LocalForwarder   │───▶│ Local Service│  │
│  │ (WebSocket)     │     │ (HTTP Client)    │     │ (port 3000)  │  │
│  └─────────────────┘     └──────────────────┘     └──────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

## Running Your Own Server

### Quick Server Start (Development)

```bash
cd burrow
mix deps.get
BURROW_MODE=server mix run --no-halt

# Or with custom port
PORT=8080 BURROW_MODE=server mix run --no-halt
```

### Production Deployment

See [docs/CLOUD_DEPLOYMENT.md](docs/CLOUD_DEPLOYMENT.md) for deploying to:

- **Fly.io** - Global edge deployment with dedicated IPs (recommended)

## Project Structure

```
burrow/
├── client/                 # Rust CLI client
│   ├── src/
│   │   ├── main.rs
│   │   ├── client/         # Connection and TUI
│   │   ├── crypto/         # Ed25519 keypair
│   │   └── protocol/       # Message types
│   └── Cargo.toml
├── lib/burrow/             # Elixir server
│   ├── server/             # Server components
│   │   ├── supervisor.ex
│   │   ├── dispatcher.ex   # Routes by hostname
│   │   ├── tunnel_endpoint.ex  # Subdomain forwarding
│   │   ├── tunnel_socket.ex    # WebSocket handler
│   │   ├── tunnel_registry.ex  # Subdomain → tunnel mapping
│   │   ├── request_forwarder.ex
│   │   └── web/            # Inspector UI (Phoenix LiveView)
│   ├── protocol/           # Tunnel protocol
│   │   ├── message.ex
│   │   └── codec.ex
│   ├── crypto/             # Ed25519 attestation
│   └── acme/               # Let's Encrypt integration
├── priv/static/            # Static assets
└── config/                 # Server configuration
```

## Development

### Server (Elixir)

```bash
# Install dependencies
mix deps.get

# Run tests
mix test

# Format code
mix format

# Start development server
BURROW_MODE=server mix run --no-halt
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

# Run with arguments
cargo run -- -s localhost -p 3000
```

## Tech Stack

**Server:**
- Elixir 1.18+ with OTP 27+
- Bandit - Pure Elixir HTTP server with TLS
- Phoenix LiveView - Request inspector UI
- JOSE/X509 - ACME certificate management

**Client:**
- Rust
- tokio - Async runtime
- tungstenite - WebSocket client
- ed25519-dalek - Ed25519 signatures
- ratatui - Terminal UI

## License

MIT
