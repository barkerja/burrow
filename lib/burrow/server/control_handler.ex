defmodule Burrow.Server.ControlHandler do
  @moduledoc """
  Handles tunnel registration and control operations.

  This module is the boundary between client registration requests
  and internal tunnel state management.
  """

  import Plug.Conn

  alias Burrow.Protocol.{Codec, Message}
  alias Burrow.Crypto.Attestation
  alias Burrow.Server.{TunnelRegistry, Subdomain}
  alias Burrow.ULID

  @doc """
  Handles a tunnel registration request.

  Validates attestation, assigns subdomain, and registers the tunnel.
  """
  @spec handle_registration(Plug.Conn.t()) :: Plug.Conn.t()
  def handle_registration(conn) do
    with {:ok, body, conn} <- read_body(conn),
         {:ok, message} <- decode_body(body),
         {:ok, attestation} <- parse_attestation(message),
         :ok <- Attestation.verify(attestation),
         {:ok, subdomain} <- assign_subdomain(attestation, message),
         {:ok, tunnel_id} <- register_tunnel(subdomain, attestation, message, conn) do
      full_url = build_url(subdomain)
      response = Message.tunnel_registered(tunnel_id, subdomain, full_url)

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Codec.encode!(response))
    else
      {:error, :empty_body} ->
        send_error(conn, 400, "empty_body", "Request body is required")

      {:error, :invalid_json} ->
        send_error(conn, 400, "invalid_json", "Invalid JSON in request body")

      {:error, :missing_attestation} ->
        send_error(conn, 400, "missing_attestation", "Attestation is required")

      {:error, :expired} ->
        send_error(conn, 401, "attestation_expired", "Attestation has expired")

      {:error, :invalid_signature} ->
        send_error(conn, 401, "invalid_signature", "Attestation signature is invalid")

      {:error, :subdomain_taken} ->
        send_error(conn, 409, "subdomain_taken", "Requested subdomain is already in use")

      {:error, reason} ->
        send_error(conn, 400, "bad_request", "Invalid request: #{inspect(reason)}")
    end
  end

  @doc """
  Handles a tunnel response from a client.

  Routes the response to the waiting request handler.
  """
  @spec handle_response(Plug.Conn.t()) :: Plug.Conn.t()
  def handle_response(conn) do
    with {:ok, body, conn} <- read_body(conn),
         {:ok, message} <- decode_body(body),
         :ok <- process_response(message) do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(%{status: "ok"}))
    else
      {:error, reason} ->
        send_error(conn, 400, "bad_request", "Invalid response: #{inspect(reason)}")
    end
  end

  # Private functions

  defp decode_body(""), do: {:error, :empty_body}
  defp decode_body(nil), do: {:error, :empty_body}

  defp decode_body(body) do
    case Codec.decode(body) do
      {:ok, message} -> {:ok, message}
      {:error, _} -> {:error, :invalid_json}
    end
  end

  defp parse_attestation(%{attestation: att_map}) when is_map(att_map) do
    Attestation.from_map(att_map)
  end

  defp parse_attestation(_), do: {:error, :missing_attestation}

  defp assign_subdomain(attestation, message) do
    requested = Map.get(message, :requested_subdomain) || attestation.requested_subdomain

    cond do
      is_nil(requested) or requested == "" ->
        {:ok, Subdomain.from_public_key(attestation.public_key)}

      not Subdomain.valid?(requested) ->
        {:ok, Subdomain.from_public_key(attestation.public_key)}

      subdomain_available?(requested) ->
        {:ok, requested}

      true ->
        {:error, :subdomain_taken}
    end
  end

  defp subdomain_available?(subdomain) do
    case TunnelRegistry.lookup(subdomain) do
      {:error, :not_found} -> true
      {:ok, _} -> false
    end
  end

  defp register_tunnel(subdomain, attestation, message, _conn) do
    tunnel_id = ULID.generate()
    stream_ref = make_ref()

    params = %{
      tunnel_id: tunnel_id,
      subdomain: subdomain,
      client_public_key: attestation.public_key,
      connection_pid: self(),
      stream_ref: stream_ref,
      local_host: Map.get(message, :local_host, "localhost"),
      local_port: Map.get(message, :local_port, 80)
    }

    case TunnelRegistry.register(params) do
      {:ok, _} -> {:ok, tunnel_id}
      {:error, reason} -> {:error, reason}
    end
  end

  defp process_response(message) do
    request_id = Map.get(message, :request_id)

    if request_id do
      Burrow.Server.PendingRequests.complete(request_id, message)
    else
      {:error, :missing_request_id}
    end
  end

  defp build_url(subdomain) do
    base_domain = Application.get_env(:burrow, :server, [])[:base_domain] || "localhost"
    "https://#{subdomain}.#{base_domain}"
  end

  defp send_error(conn, status, code, message) do
    response = Message.error(code, message)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Codec.encode!(response))
  end
end
