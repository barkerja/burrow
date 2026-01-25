defmodule Burrow.Server.Web.InspectorLive.Index do
  @moduledoc """
  LiveView for the request inspector dashboard.

  Displays real-time HTTP request/response logs flowing through tunnels.
  """

  use Phoenix.LiveView

  alias Burrow.Server.RequestStore
  alias Burrow.Server.TunnelRegistry

  @refresh_interval 5_000

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Burrow.PubSub, RequestStore.pubsub_topic())
      :timer.send_interval(@refresh_interval, self(), :refresh_tunnels)
    end

    requests = RequestStore.list_requests(limit: 100)
    tunnels = TunnelRegistry.list_tunnels()
    subdomains = TunnelRegistry.list_subdomains()
    current_user = session["current_user"]

    {:ok,
     socket
     |> assign(:requests, requests)
     |> assign(:tunnels, tunnels)
     |> assign(:subdomains, subdomains)
     |> assign(:method_filter, nil)
     |> assign(:status_filter, nil)
     |> assign(:subdomain_filter, nil)
     |> assign(:path_filter, "")
     |> assign(:request_count, RequestStore.count())
     |> assign(:current_user, current_user)}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info(:refresh_tunnels, socket) do
    tunnels = TunnelRegistry.list_tunnels()
    subdomains = TunnelRegistry.list_subdomains()
    {:noreply, socket |> assign(:tunnels, tunnels) |> assign(:subdomains, subdomains)}
  end

  def handle_info({:request_store, {:request_logged, request}}, socket) do
    requests = [request | socket.assigns.requests] |> Enum.take(100)

    {:noreply,
     socket
     |> assign(:requests, filter_requests(requests, socket.assigns))
     |> assign(:request_count, socket.assigns.request_count + 1)}
  end

  def handle_info({:request_store, {:response_logged, updated_request}}, socket) do
    requests =
      Enum.map(socket.assigns.requests, fn req ->
        if req.id == updated_request.id, do: updated_request, else: req
      end)

    {:noreply, assign(socket, :requests, requests)}
  end

  def handle_info({:request_store, {:request_updated, updated_request}}, socket) do
    requests =
      Enum.map(socket.assigns.requests, fn req ->
        if req.id == updated_request.id, do: updated_request, else: req
      end)

    {:noreply, assign(socket, :requests, requests)}
  end

  def handle_info({:request_store, :cleared}, socket) do
    {:noreply,
     socket
     |> assign(:requests, [])
     |> assign(:request_count, 0)}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("filter", params, socket) do
    method_filter = if params["method"] == "", do: nil, else: params["method"]
    status_filter = parse_status_filter(params["status"])
    subdomain_filter = if params["subdomain"] == "", do: nil, else: params["subdomain"]
    path_filter = params["path"] || ""

    socket =
      socket
      |> assign(:method_filter, method_filter)
      |> assign(:status_filter, status_filter)
      |> assign(:subdomain_filter, subdomain_filter)
      |> assign(:path_filter, path_filter)

    filters = build_filters(socket.assigns)
    requests = RequestStore.list_requests(filters ++ [limit: 100])

    {:noreply, assign(socket, :requests, requests)}
  end

  def handle_event("clear", _params, socket) do
    RequestStore.clear()
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="inspector-index">
      <!-- Active Tunnels -->
      <div class="tunnels-bar">
        <%= if @tunnels == [] do %>
          <div class="no-tunnels">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="16" height="16">
              <circle cx="12" cy="12" r="10"/>
              <line x1="12" y1="8" x2="12" y2="12"/>
              <line x1="12" y1="16" x2="12.01" y2="16"/>
            </svg>
            No active tunnels
          </div>
        <% else %>
          <div class="tunnels-label">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="14" height="14">
              <path d="M22 12h-4l-3 9L9 3l-3 9H2"/>
            </svg>
            Active Tunnels
          </div>
          <div class="tunnels-list">
            <%= for tunnel <- @tunnels do %>
              <div class="tunnel-chip">
                <span class="tunnel-subdomain"><%= tunnel.subdomain %></span>
                <span class="tunnel-arrow">→</span>
                <span class="tunnel-target"><%= tunnel.local_host %>:<%= tunnel.local_port %></span>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>

      <!-- Filters -->
      <div class="toolbar">
        <form phx-change="filter" phx-submit="filter" class="filters">
          <select name="subdomain">
            <option value="">All Tunnels</option>
            <%= for subdomain <- @subdomains do %>
              <option value={subdomain} selected={@subdomain_filter == subdomain}><%= subdomain %></option>
            <% end %>
          </select>
          <select name="method">
            <option value="">All Methods</option>
            <option value="GET" selected={@method_filter == "GET"}>GET</option>
            <option value="POST" selected={@method_filter == "POST"}>POST</option>
            <option value="PUT" selected={@method_filter == "PUT"}>PUT</option>
            <option value="PATCH" selected={@method_filter == "PATCH"}>PATCH</option>
            <option value="DELETE" selected={@method_filter == "DELETE"}>DELETE</option>
          </select>
          <select name="status">
            <option value="">All Status</option>
            <option value="2xx" selected={@status_filter == "2xx"}>2xx Success</option>
            <option value="3xx" selected={@status_filter == "3xx"}>3xx Redirect</option>
            <option value="4xx" selected={@status_filter == "4xx"}>4xx Client Error</option>
            <option value="5xx" selected={@status_filter == "5xx"}>5xx Server Error</option>
          </select>
          <input
            type="text"
            name="path"
            placeholder="Filter by path..."
            value={@path_filter}
            phx-debounce="300"
          />
          <button type="button" class="btn" phx-click="clear">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="14" height="14">
              <polyline points="3 6 5 6 21 6"/>
              <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/>
            </svg>
            Clear
          </button>
        </form>

        <%= if @current_user do %>
          <div class="user-info">
            <span class="username"><%= @current_user.username %></span>
            <form action="/auth/logout" method="post">
              <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
              <button type="submit" class="btn btn-sm">Sign Out</button>
            </form>
          </div>
        <% end %>
      </div>

      <!-- Requests Table -->
      <div class="panel">
        <div class="panel-header">
          <span class="request-count">
            <span class="count-number"><%= @request_count %></span>
            total requests
          </span>
        </div>
        <div class="table-scroll">
          <table>
            <thead>
              <tr>
                <th>Time</th>
                <th>Method</th>
                <th>Subdomain</th>
                <th>Path</th>
                <th>Status</th>
                <th>Size</th>
                <th>Duration</th>
              </tr>
            </thead>
            <tbody id="requests">
              <%= if @requests == [] do %>
                <tr>
                  <td colspan="7">
                    <div class="empty-state">
                      <p>No requests yet</p>
                      <p>Requests will appear here as they flow through your tunnels</p>
                    </div>
                  </td>
                </tr>
              <% else %>
                <%= for request <- @requests do %>
                  <tr id={"request-#{request.id}"} title={request_tooltip(request)}>
                    <td class="cell-time"><%= format_time(request.started_at) %></td>
                    <td>
                      <span class={"method method-#{String.downcase(request.method)}"}>
                        <%= request.method %>
                      </span>
                    </td>
                    <td class="cell-subdomain"><%= request.subdomain %></td>
                    <td class="cell-path">
                      <.link navigate={"/inspector/requests/#{request.id}"}>
                        <%= truncate(request.path, 50) %>
                      </.link>
                    </td>
                    <td>
                      <span class={status_class(request.status)}>
                        <%= request.status || "..." %>
                      </span>
                    </td>
                    <td class="cell-size">
                      <%= if request.response_size do %>
                        <%= format_bytes(request.response_size) %>
                      <% else %>
                        <span class="text-muted">-</span>
                      <% end %>
                    </td>
                    <td class="cell-duration">
                      <%= if request.duration_ms do %>
                        <span class="duration"><%= request.duration_ms %>ms</span>
                      <% else %>
                        <span class="text-muted">pending</span>
                      <% end %>
                    </td>
                  </tr>
                <% end %>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    </div>

    <style>
      .inspector-index {
        display: flex;
        flex-direction: column;
        gap: 1rem;
        flex: 1;
        min-height: 0;
      }

      /* Tunnels bar */
      .tunnels-bar {
        display: flex;
        align-items: center;
        gap: 1rem;
        padding: 0.75rem 1rem;
        background: var(--bg-surface);
        border: 1px solid var(--border);
        border-radius: 10px;
        flex-wrap: wrap;
      }

      .no-tunnels {
        display: flex;
        align-items: center;
        gap: 0.5rem;
        color: var(--text-muted);
        font-size: 0.875rem;
      }

      .tunnels-label {
        display: flex;
        align-items: center;
        gap: 0.5rem;
        color: var(--text-secondary);
        font-size: 0.8rem;
        font-weight: 500;
        text-transform: uppercase;
        letter-spacing: 0.05em;
      }

      .tunnels-label svg {
        color: var(--success);
      }

      .tunnels-list {
        display: flex;
        gap: 0.5rem;
        flex-wrap: wrap;
      }

      .tunnel-chip {
        display: flex;
        align-items: center;
        gap: 0.375rem;
        padding: 0.375rem 0.75rem;
        background: var(--bg-elevated);
        border: 1px solid var(--border);
        border-radius: 6px;
        font-size: 0.8rem;
      }

      .tunnel-subdomain {
        font-family: 'JetBrains Mono', monospace;
        color: var(--accent);
        font-weight: 500;
      }

      .tunnel-arrow {
        color: var(--text-muted);
      }

      .tunnel-target {
        font-family: 'JetBrains Mono', monospace;
        color: var(--text-secondary);
      }

      /* Toolbar */
      .toolbar {
        display: flex;
        justify-content: space-between;
        align-items: center;
        gap: 1rem;
        flex-wrap: wrap;
      }

      .request-count {
        color: var(--text-secondary);
        font-size: 0.875rem;
      }

      .count-number {
        font-family: 'JetBrains Mono', monospace;
        font-weight: 600;
        color: var(--text-primary);
      }

      /* Table cells */
      .cell-time {
        font-family: 'JetBrains Mono', monospace;
        font-size: 0.8rem;
        color: var(--text-muted);
      }

      .cell-subdomain {
        font-family: 'JetBrains Mono', monospace;
        font-size: 0.85rem;
        color: var(--accent);
      }

      .cell-path {
        max-width: 300px;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      .cell-size,
      .cell-duration {
        font-family: 'JetBrains Mono', monospace;
        font-size: 0.8rem;
        color: var(--text-secondary);
      }

      .duration {
        color: var(--text-primary);
      }

      .text-muted {
        color: var(--text-muted);
      }

      @media (max-width: 768px) {
        .toolbar {
          flex-direction: column;
          align-items: stretch;
        }

        .user-info {
          justify-content: flex-end;
        }

        .tunnels-bar {
          flex-direction: column;
          align-items: flex-start;
        }
      }
    </style>
    """
  end

  defp format_time(nil), do: "-"

  defp format_time(datetime) do
    Calendar.strftime(datetime, "%H:%M:%S")
  end

  defp truncate(nil, _max), do: ""
  defp truncate(string, max) when byte_size(string) <= max, do: string
  defp truncate(string, max), do: String.slice(string, 0, max) <> "..."

  defp format_bytes(nil), do: "-"
  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / (1024 * 1024), 2)} MB"

  defp request_tooltip(request) do
    ip_parts =
      if request.ip_info do
        info = request.ip_info
        location = format_location(info)

        [
          if(request.client_ip, do: "IP: #{request.client_ip}"),
          if(info.isp, do: "ISP: #{info.isp}"),
          if(location != "", do: "Location: #{location}")
        ]
      else
        [if(request.client_ip, do: "IP: #{request.client_ip}")]
      end

    other_parts = [
      if(request.user_agent, do: "UA: #{truncate(request.user_agent, 60)}"),
      if(request.content_type, do: "Request: #{request.content_type}"),
      if(request.response_content_type, do: "Response: #{request.response_content_type}"),
      if(request.request_size && request.request_size > 0,
        do: "Req Size: #{format_bytes(request.request_size)}"
      ),
      if(request.referer, do: "Referer: #{truncate(request.referer, 50)}")
    ]

    (ip_parts ++ other_parts)
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp format_location(nil), do: ""

  defp format_location(info) do
    parts =
      [info[:city], info[:region]]
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&(&1 == ""))

    case parts do
      [] -> info[:country] || ""
      _ -> Enum.join(parts, ", ")
    end
  end

  defp status_class(nil), do: "status status-pending"
  defp status_class(status) when status >= 200 and status < 300, do: "status status-2xx"
  defp status_class(status) when status >= 300 and status < 400, do: "status status-3xx"
  defp status_class(status) when status >= 400 and status < 500, do: "status status-4xx"
  defp status_class(status) when status >= 500, do: "status status-5xx"
  defp status_class(_), do: "status"

  defp parse_status_filter(""), do: nil
  defp parse_status_filter("2xx"), do: "2xx"
  defp parse_status_filter("3xx"), do: "3xx"
  defp parse_status_filter("4xx"), do: "4xx"
  defp parse_status_filter("5xx"), do: "5xx"
  defp parse_status_filter(_), do: nil

  defp build_filters(assigns) do
    []
    |> maybe_add_filter(:method, assigns.method_filter)
    |> maybe_add_filter(:status, status_range(assigns.status_filter))
    |> maybe_add_filter(:subdomain, assigns.subdomain_filter)
    |> maybe_add_filter(:path_pattern, assigns.path_filter)
  end

  defp maybe_add_filter(filters, _key, nil), do: filters
  defp maybe_add_filter(filters, _key, ""), do: filters
  defp maybe_add_filter(filters, key, value), do: [{key, value} | filters]

  defp status_range("2xx"), do: Enum.to_list(200..299)
  defp status_range("3xx"), do: Enum.to_list(300..399)
  defp status_range("4xx"), do: Enum.to_list(400..499)
  defp status_range("5xx"), do: Enum.to_list(500..599)
  defp status_range(_), do: nil

  defp filter_requests(requests, assigns) do
    filters = build_filters(assigns)

    Enum.filter(requests, fn req ->
      Enum.all?(filters, fn {key, value} -> matches?(req, key, value) end)
    end)
  end

  defp matches?(req, :method, method), do: req.method == method
  defp matches?(req, :status, statuses) when is_list(statuses), do: req.status in statuses
  defp matches?(req, :subdomain, subdomain), do: req.subdomain == subdomain

  defp matches?(req, :path_pattern, pattern) do
    case Regex.compile(pattern) do
      {:ok, regex} -> Regex.match?(regex, req.path || "")
      _ -> true
    end
  end

  defp matches?(_, _, _), do: true
end
