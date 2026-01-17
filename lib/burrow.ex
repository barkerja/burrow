defmodule Burrow do
  @moduledoc """
  Burrow - A lightweight ngrok clone in Elixir.

  Burrow enables developers to expose local web services to the internet
  through secure tunnels with subdomain-based routing.

  ## Components

  - **Server**: Public-facing HTTPS server that routes requests through tunnels
  - **Client**: CLI tool that establishes tunnels to local services

  ## Key Features

  - Subdomain-based routing (e.g., `abc123.burrow.example.com`)
  - HTTP/2 multiplexed streams for efficient tunnel transport
  - Ed25519 attestation-based authentication
  - TLS termination at the server
  """
end
