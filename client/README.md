# Burrow Client

A cross-platform CLI client for the Burrow tunnel service, written in Rust.

## Features

- Single binary with no external dependencies
- HTTP and TCP tunneling
- API token authentication
- WebSocket-based communication
- Interactive TUI with multi-view navigation
- Request/response logging and inspection
- Cross-platform (Linux, macOS, Windows)

## Installation

### From Release

Download the latest binary for your platform from the [releases page](https://github.com/barkerja/burrow/releases):

| Platform | Archive |
|----------|---------|
| Linux x86_64 | `burrow-vX.X.X-x86_64-unknown-linux-gnu.tar.gz` |
| Linux ARM64 | `burrow-vX.X.X-aarch64-unknown-linux-gnu.tar.gz` |
| macOS ARM64 | `burrow-vX.X.X-aarch64-apple-darwin.tar.gz` |
| Windows x86_64 | `burrow-vX.X.X-x86_64-pc-windows-msvc.zip` |
| Windows ARM64 | `burrow-vX.X.X-aarch64-pc-windows-msvc.zip` |

### From Source

```bash
cd client
cargo build --release
```

The binary will be at `target/release/burrow`.

## Quick Start

### 1. Authenticate

```bash
burrow login -s tunnel.example.com
```

This opens your browser to create/retrieve an API token, then saves it locally.

### 2. Start Tunnels

```bash
burrow start -s tunnel.example.com
```

This launches the interactive TUI where you can add and manage tunnels.

## Commands

### `burrow login`

Authenticate and save your API token.

```bash
burrow login -s tunnel.example.com
```

Opens the Burrow web UI in your browser where you can:
1. Register or login with a passkey
2. Create an API token
3. Paste the token when prompted

The token is saved to `~/.config/burrow/config.toml`.

### `burrow start`

Start the tunnel client in TUI mode.

```bash
burrow start -s tunnel.example.com
```

Options:
- `-H, --host <HOST>` - Local host to forward to (default: localhost)
- `--server-port <PORT>` - Server port (default: 443)
- `--no-tui` - Disable TUI (requires pre-configured tunnels)

### `burrow subdomains`

Manage your subdomain reservations.

```bash
# List reservations (opens web UI)
burrow subdomains -s tunnel.example.com

# Release a reservation
burrow subdomains release myapp -s tunnel.example.com
```

## Global Options

```
-s, --server <HOST>     Server hostname (or set BURROW_SERVER env var)
-k, --token <TOKEN>     API token (or set BURROW_TOKEN env var)
-v, --verbose           Enable verbose logging
-h, --help              Print help
-V, --version           Print version
```

## Configuration

Configuration is stored in `~/.config/burrow/config.toml`:

```toml
[auth]
token = "your-api-token"
server = "tunnel.example.com"
```

Environment variables take precedence over the config file:
- `BURROW_SERVER` - Server hostname
- `BURROW_TOKEN` - API token

## TUI Navigation

The TUI has multiple views:

### Tunnel List View
- `↑/↓` - Navigate tunnels
- `a` - Add new tunnel
- `Tab` - Switch to request list
- `q` - Quit

### Add Tunnel View
- `Tab` - Switch between fields
- `↑/↓` - Change tunnel type (HTTP/TCP)
- `Enter` - Submit
- `Esc` - Cancel

### Request List View
- `↑/↓` - Navigate requests
- `Enter` - View request details
- `Tab` - Switch to tunnel list
- `q` - Quit

### Request Detail View
- `Esc` - Go back to list

## Building for Different Platforms

### Linux (x86_64)

```bash
cargo build --release --target x86_64-unknown-linux-gnu
```

### Linux (ARM64)

```bash
# Using cross for cross-compilation
cargo install cross
cross build --release --target aarch64-unknown-linux-gnu
```

### macOS (Apple Silicon)

```bash
cargo build --release --target aarch64-apple-darwin
```

### Windows (x86_64)

```bash
cargo build --release --target x86_64-pc-windows-msvc
```

### Windows (ARM64)

```bash
cargo build --release --target aarch64-pc-windows-msvc
```

## Development

```bash
# Run in development
cargo run -- start -s tunnel.example.com

# Run tests
cargo test

# Check formatting
cargo fmt -- --check

# Lint
cargo clippy
```

## Architecture

```
src/
├── main.rs           # CLI entry point and command routing
├── config.rs         # Configuration management (~/.config/burrow/config.toml)
├── error.rs          # Error types
├── client/
│   ├── mod.rs        # TunnelClient - main client logic
│   ├── connection.rs # WebSocket connection to server
│   ├── http_proxy.rs # HTTP request forwarding
│   ├── ws_proxy.rs   # WebSocket forwarding
│   └── tui/
│       ├── mod.rs    # TUI application state
│       ├── ui.rs     # UI rendering (ratatui)
│       └── events.rs # Event types
├── protocol/
│   ├── mod.rs        # Protocol module
│   ├── messages.rs   # Message types (JSON)
│   └── ids.rs        # Type-safe ID wrappers
└── crypto/
    └── mod.rs        # (Reserved for future use)
```

## License

MIT
