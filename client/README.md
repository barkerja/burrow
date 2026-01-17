# Burrow Client

A cross-platform CLI client for the Burrow tunnel service, written in Rust.

## Features

- Single binary with no external dependencies
- HTTP and TCP tunneling
- Ed25519 authentication
- WebSocket-based communication
- Interactive TUI with request logging
- Cross-platform (Linux, macOS, Windows)

## Installation

### From Release

Download the latest binary for your platform from the [releases page](https://github.com/barkerja/burrow/releases).

### From Source

```bash
cd client
cargo build --release
```

The binary will be at `target/release/burrow`.

## Usage

```bash
# Basic HTTP tunnel
./burrow -s tunnel.example.com -p 3000

# With custom subdomain
./burrow -s tunnel.example.com -p 3000 -d myapp

# Multiple HTTP tunnels
./burrow -s tunnel.example.com -p 3000 -p 4000:api

# TCP tunnel for database
./burrow -s tunnel.example.com -p 3000 --tcp 5432

# With existing keypair
./burrow -s tunnel.example.com -p 3000 -k ~/.burrow/keypair.json
```

## Options

```
USAGE:
    burrow [OPTIONS] --server <SERVER> --port <PORT>...

OPTIONS:
    -s, --server <SERVER>      Server hostname
    -p, --port <PORT>...       Local HTTP port (can specify multiple)
                               Format: PORT or PORT:SUBDOMAIN
    -t, --tcp <PORT>...        Local TCP port to tunnel
    -H, --host <HOST>          Local host [default: localhost]
    -d, --subdomain <NAME>     Requested subdomain (for single tunnel)
    -k, --keypair <PATH>       Path to keypair file
        --server-port <PORT>   Server port [default: 443]
    -v, --verbose              Enable verbose logging
    -h, --help                 Print help
    -V, --version              Print version
```

## Keypair Format

Keypairs are stored in `~/.burrow/keypair.json`:

```json
{
  "public_key": "base64-encoded-public-key",
  "secret_key": "base64-encoded-secret-key"
}
```

A keypair is automatically generated on first run if one doesn't exist.

## Building for Different Platforms

### Linux (x86_64)

```bash
cargo build --release --target x86_64-unknown-linux-gnu
```

### Linux (ARM64)

```bash
cargo build --release --target aarch64-unknown-linux-gnu
```

### macOS (Intel)

```bash
cargo build --release --target x86_64-apple-darwin
```

### macOS (Apple Silicon)

```bash
cargo build --release --target aarch64-apple-darwin
```

### Windows

```bash
cargo build --release --target x86_64-pc-windows-msvc
```

## Development

```bash
# Run in development
cargo run -- -s tunnel.example.com -p 3000

# Run tests
cargo test

# Check formatting
cargo fmt -- --check

# Lint
cargo clippy
```

## License

MIT
