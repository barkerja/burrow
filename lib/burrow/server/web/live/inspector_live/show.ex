defmodule Burrow.Server.Web.InspectorLive.Show do
  @moduledoc """
  LiveView for detailed request inspection.

  Shows full request/response details including headers and body.
  """

  use Phoenix.LiveView

  alias Burrow.Server.RequestStore

  @impl true
  def mount(%{"id" => request_id}, _session, socket) do
    case RequestStore.get_request(request_id) do
      {:ok, request} ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(Burrow.PubSub, RequestStore.pubsub_topic())
        end

        {:ok,
         socket
         |> assign(:request, request)
         |> assign(:curl_command, build_curl_command(request))}

      {:error, :not_found} ->
        {:ok,
         socket
         |> assign(:request, nil)
         |> assign(:curl_command, nil)}
    end
  end

  @impl true
  def handle_info({:request_store, {:response_logged, updated}}, socket) do
    if socket.assigns.request && socket.assigns.request.id == updated.id do
      {:noreply,
       socket
       |> assign(:request, updated)
       |> assign(:curl_command, build_curl_command(updated))}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:request_store, {:request_updated, updated}}, socket) do
    if socket.assigns.request && socket.assigns.request.id == updated.id do
      {:noreply, assign(socket, :request, updated)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("copy_curl", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="request-show">
      <.link navigate="/inspector" class="back-link">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="16" height="16">
          <line x1="19" y1="12" x2="5" y2="12"/>
          <polyline points="12 19 5 12 12 5"/>
        </svg>
        Back to requests
      </.link>

      <%= if @request do %>
        <div class="request-header panel">
          <div class="panel-header">
            <div class="request-summary">
              <span class={"method method-#{String.downcase(@request.method)}"}><%= @request.method %></span>
              <span class="request-url">
                <span class="subdomain"><%= @request.subdomain %></span>.<%= get_base_domain() %><%= @request.path %>
              </span>
            </div>
            <span class={status_class(@request.status)}>
              <%= @request.status || "Pending" %>
            </span>
          </div>
          <div class="panel-body">
            <div class="meta-grid">
              <div class="meta-item">
                <span class="meta-label">Started</span>
                <span class="meta-value">
                  <local-time utc={format_utc(@request.started_at)} format="full"></local-time>
                </span>
              </div>
              <div class="meta-item">
                <span class="meta-label">Duration</span>
                <span class="meta-value"><%= if @request.duration_ms, do: "#{@request.duration_ms}ms", else: "pending..." %></span>
              </div>
              <div class="meta-item">
                <span class="meta-label">Request Size</span>
                <span class="meta-value"><%= format_bytes(@request.request_size) %></span>
              </div>
              <div class="meta-item">
                <span class="meta-label">Response Size</span>
                <span class="meta-value"><%= format_bytes(@request.response_size) %></span>
              </div>
            </div>
            <div class="meta-grid">
              <div class="meta-item">
                <span class="meta-label">Client IP</span>
                <span class="meta-value">
                  <%= @request.client_ip || "-" %>
                  <%= if @request.ip_info && @request.ip_info[:isp] do %>
                    <span class="meta-secondary"><%= @request.ip_info.isp %></span>
                  <% end %>
                </span>
              </div>
              <div class="meta-item">
                <span class="meta-label">Location</span>
                <span class="meta-value"><%= format_location(@request.ip_info) %></span>
              </div>
              <div class="meta-item">
                <span class="meta-label">Content-Type</span>
                <span class="meta-value mono"><%= @request.content_type || "-" %></span>
              </div>
              <div class="meta-item">
                <span class="meta-label">Response Type</span>
                <span class="meta-value mono"><%= @request.response_content_type || "-" %></span>
              </div>
            </div>
            <%= if @request.user_agent do %>
              <div class="meta-full">
                <span class="meta-label">User-Agent</span>
                <span class="meta-value mono"><%= @request.user_agent %></span>
              </div>
            <% end %>
            <%= if @request.referer do %>
              <div class="meta-full">
                <span class="meta-label">Referer</span>
                <span class="meta-value mono"><%= @request.referer %></span>
              </div>
            <% end %>
          </div>
        </div>

        <div class="detail-grid">
          <div>
            <div class="panel">
              <div class="panel-header">
                <span>Request Headers</span>
              </div>
              <div class="panel-body">
                <div class="code-block">
                  <%= for {name, value} <- @request.headers || [] do %>
                    <div class="header-line"><span class="header-name"><%= name %>:</span> <%= value %></div>
                  <% end %>
                  <%= if (@request.headers || []) == [] do %>
                    <span class="no-content">No headers</span>
                  <% end %>
                </div>
              </div>
            </div>

            <div class="panel">
              <div class="panel-header">
                <span>Request Body</span>
              </div>
              <div class="panel-body">
                <div class="code-block">
                  <%= if @request.body && @request.body != "" do %>
                    <pre><%= format_body(@request.body) %></pre>
                  <% else %>
                    <span class="no-content">No body</span>
                  <% end %>
                </div>
              </div>
            </div>
          </div>

          <div>
            <div class="panel">
              <div class="panel-header">
                <span>Response Headers</span>
              </div>
              <div class="panel-body">
                <div class="code-block">
                  <%= if @request.response_headers do %>
                    <%= for header <- @request.response_headers do %>
                      <%= case header do %>
                        <% [name, value] -> %>
                          <div class="header-line"><span class="header-name"><%= name %>:</span> <%= value %></div>
                        <% {name, value} -> %>
                          <div class="header-line"><span class="header-name"><%= name %>:</span> <%= value %></div>
                        <% _ -> %>
                      <% end %>
                    <% end %>
                    <%= if @request.response_headers == [] do %>
                      <span class="no-content">No headers</span>
                    <% end %>
                  <% else %>
                    <span class="no-content awaiting">Awaiting response...</span>
                  <% end %>
                </div>
              </div>
            </div>

            <div class="panel">
              <div class="panel-header">
                <span>Response Body</span>
              </div>
              <div class="panel-body">
                <div class="code-block">
                  <%= if @request.response_body && @request.response_body != "" do %>
                    <pre><%= format_body(@request.response_body) %></pre>
                  <% else %>
                    <span class="no-content">
                      <%= if @request.status, do: "No body", else: "Awaiting response..." %>
                    </span>
                  <% end %>
                </div>
              </div>
            </div>
          </div>
        </div>

        <div class="panel curl-panel">
          <div class="panel-header">
            <span>cURL Command</span>
            <button class="btn btn-sm" onclick={"navigator.clipboard.writeText(document.getElementById('curl-cmd').textContent)"}>
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="12" height="12">
                <rect x="9" y="9" width="13" height="13" rx="2" ry="2"/>
                <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/>
              </svg>
              Copy
            </button>
          </div>
          <div class="panel-body">
            <div class="code-block curl-block" id="curl-cmd"><%= @curl_command %></div>
          </div>
        </div>
      <% else %>
        <div class="panel">
          <div class="panel-body">
            <div class="empty-state">
              <p>Request not found</p>
            </div>
          </div>
        </div>
      <% end %>
    </div>

    <style>
      .request-show {
        display: flex;
        flex-direction: column;
        gap: 1rem;
        flex: 1;
        min-height: 0;
      }

      .back-link {
        display: inline-flex;
        align-items: center;
        gap: 0.5rem;
        color: var(--text-secondary);
        font-size: 0.875rem;
        margin-bottom: 0.5rem;
        transition: color 0.15s ease;
      }

      .back-link:hover {
        color: var(--accent);
      }

      .request-header {
        flex-shrink: 0;
      }

      .request-summary {
        display: flex;
        align-items: center;
        gap: 0.75rem;
      }

      .request-url {
        font-family: 'JetBrains Mono', monospace;
        font-size: 0.9rem;
        color: var(--text-secondary);
        word-break: break-all;
      }

      .request-url .subdomain {
        color: var(--accent);
      }

      .meta-grid {
        display: grid;
        grid-template-columns: repeat(4, 1fr);
        gap: 1rem;
        margin-bottom: 1rem;
      }

      .meta-item {
        display: flex;
        flex-direction: column;
        gap: 0.25rem;
      }

      .meta-label {
        font-size: 0.7rem;
        text-transform: uppercase;
        letter-spacing: 0.05em;
        color: var(--text-muted);
        font-weight: 500;
      }

      .meta-value {
        font-size: 0.9rem;
        color: var(--text-primary);
      }

      .meta-value.mono {
        font-family: 'JetBrains Mono', monospace;
        font-size: 0.8rem;
        word-break: break-all;
      }

      .meta-secondary {
        display: block;
        font-size: 0.75rem;
        color: var(--text-muted);
        margin-top: 0.125rem;
      }

      .meta-full {
        display: flex;
        flex-direction: column;
        gap: 0.25rem;
        margin-bottom: 0.75rem;
      }

      .meta-full:last-child {
        margin-bottom: 0;
      }

      .header-line {
        margin-bottom: 0.25rem;
      }

      .header-name {
        color: var(--accent);
      }

      .no-content {
        color: var(--text-muted);
        font-style: italic;
      }

      .no-content.awaiting {
        animation: pulse 2s ease-in-out infinite;
      }

      @keyframes pulse {
        0%, 100% { opacity: 1; }
        50% { opacity: 0.5; }
      }

      .curl-panel {
        flex-shrink: 0;
      }

      .curl-block {
        max-height: 100px;
        font-size: 0.75rem;
      }

      @media (max-width: 768px) {
        .meta-grid {
          grid-template-columns: repeat(2, 1fr);
        }

        .request-summary {
          flex-direction: column;
          align-items: flex-start;
          gap: 0.5rem;
        }
      }
    </style>
    """
  end

  defp status_class(nil), do: "status status-pending"
  defp status_class(status) when status >= 200 and status < 300, do: "status status-2xx"
  defp status_class(status) when status >= 300 and status < 400, do: "status status-3xx"
  defp status_class(status) when status >= 400 and status < 500, do: "status status-4xx"
  defp status_class(status) when status >= 500, do: "status status-5xx"
  defp status_class(_), do: "status"

  defp format_utc(nil), do: ""

  defp format_utc(datetime) do
    DateTime.to_iso8601(datetime)
  end

  defp format_bytes(nil), do: "-"
  defp format_bytes(0), do: "0 B"
  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / (1024 * 1024), 2)} MB"

  defp format_location(nil), do: "-"

  defp format_location(info) do
    parts =
      [info[:city], info[:region]]
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&(&1 == ""))

    case parts do
      [] -> info[:country] || "-"
      _ -> Enum.join(parts, ", ")
    end
  end

  defp format_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> Jason.encode!(decoded, pretty: true)
      _ -> body
    end
  rescue
    _ -> body
  end

  defp format_body(body), do: inspect(body)

  defp get_base_domain do
    Application.get_env(:burrow, :server, [])[:base_domain] || "localhost"
  end

  defp build_curl_command(request) do
    base_domain = get_base_domain()
    url = "https://#{request.subdomain}.#{base_domain}#{request.path}"

    headers =
      (request.headers || [])
      |> Enum.reject(fn {name, _} ->
        String.downcase(name) in ["host", "content-length"]
      end)
      |> Enum.map(fn {name, value} ->
        ~s(-H "#{name}: #{escape_shell(value)}")
      end)
      |> Enum.join(" \\\n  ")

    method_flag =
      case request.method do
        "GET" -> ""
        "POST" -> "-X POST"
        "PUT" -> "-X PUT"
        "PATCH" -> "-X PATCH"
        "DELETE" -> "-X DELETE"
        other -> "-X #{other}"
      end

    body_flag =
      if request.body && request.body != "" do
        ~s(-d '#{escape_shell(request.body)}')
      else
        ""
      end

    parts =
      ["curl", method_flag, headers, body_flag, ~s("#{url}")]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join(" \\\n  ")

    parts
  end

  defp escape_shell(string) when is_binary(string) do
    string
    |> String.replace("\\", "\\\\")
    |> String.replace("'", "\\'")
    |> String.replace("\"", "\\\"")
  end

  defp escape_shell(other), do: inspect(other)
end
