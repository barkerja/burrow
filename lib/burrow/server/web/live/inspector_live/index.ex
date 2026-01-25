defmodule Burrow.Server.Web.InspectorLive.Index do
  @moduledoc """
  LiveView for the request inspector dashboard.

  Displays real-time HTTP request/response logs flowing through tunnels.
  Uses Phoenix Streams with infinite scroll for efficient handling of large request volumes.
  URL query params control filtering and tab selection.
  """

  use Phoenix.LiveView

  alias Burrow.Accounts
  alias Burrow.Server.RequestStore
  alias Burrow.Server.TunnelRegistry

  @refresh_interval 5_000
  @page_size 50
  @stream_limit 100

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Burrow.PubSub, RequestStore.pubsub_topic())
      :timer.send_interval(@refresh_interval, self(), :refresh_tunnels)
    end

    current_user = session["current_user"]
    user = if current_user, do: Accounts.get_user(current_user.id)
    is_admin = user && user.is_admin
    user_subdomains = if user, do: Accounts.list_subdomain_names(user.id), else: []

    tunnels = load_tunnels(user, false, user_subdomains)
    subdomains = load_subdomains(false, user_subdomains)

    {:ok,
     socket
     |> assign(:tunnels, tunnels)
     |> assign(:subdomains, subdomains)
     |> assign(:current_user, current_user)
     |> assign(:user, user)
     |> assign(:is_admin, is_admin)
     |> assign(:admin_mode, false)
     |> assign(:user_subdomains, user_subdomains)
     |> assign(:request_count, RequestStore.count())
     |> assign(:unknown_request_count, RequestStore.unknown_request_count())
     |> assign(:loading, false)
     |> assign(:cursor_bottom, nil)
     |> assign(:has_more_bottom, false)
     |> assign(:unknown_cursor_bottom, nil)
     |> assign(:unknown_has_more_bottom, false)}
  end

  defp load_tunnels(_user, true, _user_subdomains) do
    TunnelRegistry.list_tunnels()
  end

  defp load_tunnels(_user, false, user_subdomains) do
    TunnelRegistry.list_tunnels()
    |> Enum.filter(fn t -> t.subdomain in user_subdomains end)
  end

  defp load_subdomains(true, _user_subdomains) do
    TunnelRegistry.list_subdomains()
  end

  defp load_subdomains(false, user_subdomains) do
    TunnelRegistry.list_subdomains()
    |> Enum.filter(fn s -> s in user_subdomains end)
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab = parse_tab(params["tab"])
    method_filter = non_empty(params["method"])
    status_filter = parse_status_filter(params["status"])
    subdomain_filter = non_empty(params["subdomain"])
    path_filter = params["path"] || ""

    socket =
      socket
      |> assign(:active_tab, tab)
      |> assign(:method_filter, method_filter)
      |> assign(:status_filter, status_filter)
      |> assign(:subdomain_filter, subdomain_filter)
      |> assign(:path_filter, path_filter)

    socket =
      case tab do
        :requests -> load_requests(socket)
        :unknown_requests -> load_unknown_requests(socket)
      end

    {:noreply, socket}
  end

  defp load_requests(socket) do
    filters = build_filter_opts(socket.assigns)
    {requests, has_more?} = RequestStore.list_requests_paginated([limit: @page_size] ++ filters)

    cursor_bottom =
      if requests != [] do
        List.last(requests).started_at
      else
        nil
      end

    socket
    |> stream(:requests, requests, reset: true, limit: @stream_limit)
    |> assign(:cursor_bottom, cursor_bottom)
    |> assign(:has_more_bottom, has_more?)
    |> assign(:request_count, RequestStore.count())
  end

  defp load_unknown_requests(socket) do
    {requests, has_more?} = RequestStore.list_unknown_requests_paginated(limit: @page_size)

    cursor_bottom =
      if requests != [] do
        List.last(requests).requested_at
      else
        nil
      end

    socket
    |> stream(:unknown_requests, requests, reset: true, limit: @stream_limit)
    |> assign(:unknown_cursor_bottom, cursor_bottom)
    |> assign(:unknown_has_more_bottom, has_more?)
    |> assign(:unknown_request_count, RequestStore.unknown_request_count())
  end

  @impl true
  def handle_info(:refresh_tunnels, socket) do
    tunnels =
      load_tunnels(socket.assigns.user, socket.assigns.admin_mode, socket.assigns.user_subdomains)

    subdomains = load_subdomains(socket.assigns.admin_mode, socket.assigns.user_subdomains)
    {:noreply, socket |> assign(:tunnels, tunnels) |> assign(:subdomains, subdomains)}
  end

  def handle_info({:request_store, {:request_logged, request}}, socket) do
    socket =
      socket
      |> update(:request_count, &(&1 + 1))
      |> maybe_insert_request(request)

    {:noreply, socket}
  end

  def handle_info({:request_store, {:response_logged, updated_request}}, socket) do
    if socket.assigns.active_tab == :requests do
      {:noreply, stream_insert(socket, :requests, updated_request)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:request_store, {:request_updated, updated_request}}, socket) do
    if socket.assigns.active_tab == :requests do
      {:noreply, stream_insert(socket, :requests, updated_request)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:request_store, :cleared}, socket) do
    socket =
      socket
      |> assign(:request_count, 0)

    socket =
      if socket.assigns.active_tab == :requests do
        socket
        |> stream(:requests, [], reset: true)
        |> assign(:cursor_bottom, nil)
        |> assign(:has_more_bottom, false)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info({:request_store, {:unknown_request_logged, request}}, socket) do
    socket =
      socket
      |> update(:unknown_request_count, &(&1 + 1))

    socket =
      if socket.assigns.active_tab == :unknown_requests do
        stream_insert(socket, :unknown_requests, request, at: 0, limit: @stream_limit)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info({:request_store, {:unknown_request_updated, updated_request}}, socket) do
    if socket.assigns.active_tab == :unknown_requests do
      {:noreply, stream_insert(socket, :unknown_requests, updated_request)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:request_store, :unknown_requests_cleared}, socket) do
    socket =
      socket
      |> assign(:unknown_request_count, 0)

    socket =
      if socket.assigns.active_tab == :unknown_requests do
        socket
        |> stream(:unknown_requests, [], reset: true)
        |> assign(:unknown_cursor_bottom, nil)
        |> assign(:unknown_has_more_bottom, false)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  defp maybe_insert_request(socket, request) do
    if socket.assigns.active_tab == :requests and matches_filters?(request, socket.assigns) do
      stream_insert(socket, :requests, request, at: 0, limit: @stream_limit)
    else
      socket
    end
  end

  @impl true
  def handle_event("switch-tab", %{"tab" => tab}, socket) do
    {:noreply, push_patch(socket, to: build_path(socket, tab: tab))}
  end

  def handle_event("filter", params, socket) do
    {:noreply,
     push_patch(socket,
       to:
         build_path(socket,
           method: params["method"],
           status: params["status"],
           subdomain: params["subdomain"],
           path: params["path"]
         )
     )}
  end

  def handle_event("load-more", _params, socket) do
    if socket.assigns.loading or not socket.assigns.has_more_bottom do
      {:noreply, socket}
    else
      socket = assign(socket, :loading, true)

      filters = build_filter_opts(socket.assigns)

      {requests, has_more?} =
        RequestStore.list_requests_paginated(
          [limit: @page_size, cursor: socket.assigns.cursor_bottom, direction: :before] ++ filters
        )

      cursor_bottom =
        if requests != [] do
          List.last(requests).started_at
        else
          socket.assigns.cursor_bottom
        end

      socket =
        requests
        |> Enum.reduce(socket, fn request, acc ->
          stream_insert(acc, :requests, request, at: -1, limit: @stream_limit)
        end)
        |> assign(:cursor_bottom, cursor_bottom)
        |> assign(:has_more_bottom, has_more?)
        |> assign(:loading, false)

      {:noreply, socket}
    end
  end

  def handle_event("load-more-unknown", _params, socket) do
    if socket.assigns.loading or not socket.assigns.unknown_has_more_bottom do
      {:noreply, socket}
    else
      socket = assign(socket, :loading, true)

      {requests, has_more?} =
        RequestStore.list_unknown_requests_paginated(
          limit: @page_size,
          cursor: socket.assigns.unknown_cursor_bottom,
          direction: :before
        )

      cursor_bottom =
        if requests != [] do
          List.last(requests).requested_at
        else
          socket.assigns.unknown_cursor_bottom
        end

      socket =
        requests
        |> Enum.reduce(socket, fn request, acc ->
          stream_insert(acc, :unknown_requests, request, at: -1, limit: @stream_limit)
        end)
        |> assign(:unknown_cursor_bottom, cursor_bottom)
        |> assign(:unknown_has_more_bottom, has_more?)
        |> assign(:loading, false)

      {:noreply, socket}
    end
  end

  def handle_event("clear", _params, socket) do
    RequestStore.clear()
    {:noreply, socket}
  end

  def handle_event("clear-unknown", _params, socket) do
    RequestStore.clear_unknown_requests()
    {:noreply, socket}
  end

  def handle_event("toggle-admin-mode", _params, socket) do
    if socket.assigns.is_admin do
      new_admin_mode = !socket.assigns.admin_mode
      tunnels = load_tunnels(socket.assigns.user, new_admin_mode, socket.assigns.user_subdomains)
      subdomains = load_subdomains(new_admin_mode, socket.assigns.user_subdomains)

      socket =
        socket
        |> assign(:admin_mode, new_admin_mode)
        |> assign(:tunnels, tunnels)
        |> assign(:subdomains, subdomains)

      socket =
        case socket.assigns.active_tab do
          :requests -> load_requests(socket)
          :unknown_requests -> load_unknown_requests(socket)
        end

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  defp build_path(socket, overrides) do
    assigns = socket.assigns

    params =
      %{
        tab: Keyword.get(overrides, :tab, assigns.active_tab),
        method: Keyword.get(overrides, :method, assigns.method_filter),
        status: Keyword.get(overrides, :status, assigns.status_filter),
        subdomain: Keyword.get(overrides, :subdomain, assigns.subdomain_filter),
        path: Keyword.get(overrides, :path, assigns.path_filter)
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" or v == :requests end)
      |> Map.new()

    if map_size(params) == 0 do
      "/inspector"
    else
      "/inspector?" <> URI.encode_query(params)
    end
  end

  defp parse_tab("unknown_requests"), do: :unknown_requests
  defp parse_tab(_), do: :requests

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

      <!-- Tabs -->
      <div class="tabs">
        <button
          class={"tab #{if @active_tab == :requests, do: "active"}"}
          phx-click="switch-tab"
          phx-value-tab="requests"
        >
          Requests
          <span class="tab-count"><%= @request_count %></span>
        </button>
        <button
          class={"tab #{if @active_tab == :unknown_requests, do: "active"}"}
          phx-click="switch-tab"
          phx-value-tab="unknown_requests"
        >
          Unknown
          <span class={"tab-count #{if @unknown_request_count > 0, do: "warning"}"}><%= @unknown_request_count %></span>
        </button>
      </div>

      <%= if @active_tab == :requests do %>
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
              <%= if @is_admin do %>
                <button
                  type="button"
                  class={"btn btn-sm admin-toggle #{if @admin_mode, do: "active"}"}
                  phx-click="toggle-admin-mode"
                  title={if @admin_mode, do: "Viewing all tunnels", else: "Viewing your tunnels only"}
                >
                  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="14" height="14">
                    <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>
                  </svg>
                  <%= if @admin_mode, do: "Admin Mode", else: "My Tunnels" %>
                </button>
              <% end %>
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
              <span class="db-badge">DB</span>
            </span>
            <%= if @loading do %>
              <span class="loading-indicator">Loading...</span>
            <% end %>
          </div>
          <div class="table-scroll" id="requests-scroll">
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
              <tbody id="requests" phx-update="stream">
                <%= for {dom_id, request} <- @streams.requests do %>
                  <tr id={dom_id} title={request_tooltip(request)}>
                    <td class="cell-time">
                      <local-time utc={format_utc(request.started_at)}></local-time>
                    </td>
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
              </tbody>
            </table>
            <%= if @has_more_bottom do %>
              <div
                id="infinite-scroll-marker"
                phx-hook="InfiniteScroll"
                data-event="load-more"
                class="scroll-loader"
              >
                <%= if @loading do %>
                  <span>Loading more...</span>
                <% else %>
                  <span>Scroll for more</span>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>
      <% else %>
        <!-- Unknown Requests Toolbar -->
        <div class="toolbar">
          <div class="toolbar-info">
            <span class="info-text">Requests to non-existent tunnels</span>
          </div>
          <button type="button" class="btn" phx-click="clear-unknown">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="14" height="14">
              <polyline points="3 6 5 6 21 6"/>
              <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/>
            </svg>
            Clear
          </button>
        </div>

        <!-- Unknown Requests Table -->
        <div class="panel">
          <div class="panel-header">
            <span class="request-count">
              <span class="count-number"><%= @unknown_request_count %></span>
              unknown requests
              <span class="db-badge">DB</span>
            </span>
            <%= if @loading do %>
              <span class="loading-indicator">Loading...</span>
            <% end %>
          </div>
          <div class="table-scroll" id="unknown-requests-scroll">
            <table>
              <thead>
                <tr>
                  <th>Time</th>
                  <th>Method</th>
                  <th>Subdomain</th>
                  <th>Path</th>
                  <th>Client IP</th>
                  <th>Location</th>
                </tr>
              </thead>
              <tbody id="unknown-requests" phx-update="stream">
                <%= for {dom_id, request} <- @streams.unknown_requests do %>
                  <tr id={dom_id} title={unknown_request_tooltip(request)}>
                    <td class="cell-time">
                      <local-time utc={format_utc(request.requested_at)}></local-time>
                    </td>
                    <td>
                      <span class={"method method-#{String.downcase(request.method)}"}>
                        <%= request.method %>
                      </span>
                    </td>
                    <td class="cell-subdomain cell-unknown"><%= request.subdomain %></td>
                    <td class="cell-path"><%= truncate(request.path, 50) %></td>
                    <td class="cell-ip"><%= request.client_ip || "-" %></td>
                    <td class="cell-location"><%= format_location(request.ip_info) %></td>
                  </tr>
                <% end %>
              </tbody>
            </table>
            <%= if @unknown_has_more_bottom do %>
              <div
                id="unknown-infinite-scroll-marker"
                phx-hook="InfiniteScroll"
                data-event="load-more-unknown"
                class="scroll-loader"
              >
                <%= if @loading do %>
                  <span>Loading more...</span>
                <% else %>
                  <span>Scroll for more</span>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>

    <style>
      .inspector-index {
        display: flex;
        flex-direction: column;
        gap: 1rem;
        flex: 1;
        min-height: 0;
      }

      /* Tabs */
      .tabs {
        display: flex;
        gap: 0.25rem;
        background: var(--bg-surface);
        padding: 0.25rem;
        border-radius: 8px;
        border: 1px solid var(--border);
        width: fit-content;
      }

      .tab {
        display: flex;
        align-items: center;
        gap: 0.5rem;
        padding: 0.5rem 1rem;
        background: transparent;
        border: none;
        border-radius: 6px;
        color: var(--text-secondary);
        font-size: 0.875rem;
        font-weight: 500;
        cursor: pointer;
        transition: all 0.15s ease;
      }

      .tab:hover {
        color: var(--text-primary);
        background: var(--bg-elevated);
      }

      .tab.active {
        background: var(--bg-elevated);
        color: var(--text-primary);
        box-shadow: 0 1px 2px rgba(0, 0, 0, 0.1);
      }

      .tab-count {
        font-family: 'JetBrains Mono', monospace;
        font-size: 0.75rem;
        padding: 0.125rem 0.375rem;
        background: var(--bg-surface);
        border-radius: 4px;
      }

      .tab-count.warning {
        background: var(--warning-subtle, rgba(245, 158, 11, 0.15));
        color: var(--warning, #f59e0b);
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

      .toolbar-info {
        display: flex;
        align-items: center;
        gap: 0.5rem;
      }

      .user-info {
        display: flex;
        align-items: center;
        gap: 0.75rem;
      }

      .username {
        font-size: 0.875rem;
        color: var(--text-secondary);
      }

      .admin-toggle {
        display: flex;
        align-items: center;
        gap: 0.375rem;
      }

      .admin-toggle.active {
        background: var(--accent-subtle);
        border-color: var(--accent);
        color: var(--accent);
      }

      .info-text {
        color: var(--text-muted);
        font-size: 0.875rem;
      }

      .request-count {
        color: var(--text-secondary);
        font-size: 0.875rem;
        display: flex;
        align-items: center;
        gap: 0.5rem;
      }

      .count-number {
        font-family: 'JetBrains Mono', monospace;
        font-weight: 600;
        color: var(--text-primary);
      }

      .db-badge {
        font-size: 0.65rem;
        font-weight: 600;
        padding: 0.125rem 0.375rem;
        background: var(--accent-subtle);
        color: var(--accent);
        border-radius: 4px;
        text-transform: uppercase;
        letter-spacing: 0.05em;
      }

      .loading-indicator {
        font-size: 0.75rem;
        color: var(--text-muted);
        animation: pulse 1.5s ease-in-out infinite;
      }

      @keyframes pulse {
        0%, 100% { opacity: 1; }
        50% { opacity: 0.5; }
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

      .cell-subdomain.cell-unknown {
        color: var(--warning, #f59e0b);
      }

      .cell-path {
        max-width: 300px;
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
      }

      .cell-ip,
      .cell-location {
        font-family: 'JetBrains Mono', monospace;
        font-size: 0.8rem;
        color: var(--text-secondary);
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

      /* Infinite scroll loader */
      .scroll-loader {
        display: flex;
        justify-content: center;
        align-items: center;
        padding: 1rem;
        color: var(--text-muted);
        font-size: 0.875rem;
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

  defp format_utc(nil), do: ""

  defp format_utc(datetime) do
    DateTime.to_iso8601(datetime)
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
          if(info["isp"], do: "ISP: #{info["isp"]}"),
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

  defp unknown_request_tooltip(request) do
    ip_parts =
      if request.ip_info do
        info = request.ip_info
        location = format_location(info)

        [
          if(request.client_ip, do: "IP: #{request.client_ip}"),
          if(info["isp"], do: "ISP: #{info["isp"]}"),
          if(location != "", do: "Location: #{location}")
        ]
      else
        [if(request.client_ip, do: "IP: #{request.client_ip}")]
      end

    other_parts = [
      if(request.user_agent, do: "UA: #{truncate(request.user_agent, 60)}"),
      if(request.referer, do: "Referer: #{truncate(request.referer, 50)}")
    ]

    (ip_parts ++ other_parts)
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp format_location(nil), do: ""

  defp format_location(info) when is_map(info) do
    parts =
      [info["city"], info["region"]]
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&(&1 == ""))

    case parts do
      [] -> info["country"] || ""
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
  defp parse_status_filter(nil), do: nil
  defp parse_status_filter("2xx"), do: "2xx"
  defp parse_status_filter("3xx"), do: "3xx"
  defp parse_status_filter("4xx"), do: "4xx"
  defp parse_status_filter("5xx"), do: "5xx"
  defp parse_status_filter(_), do: nil

  defp non_empty(""), do: nil
  defp non_empty(nil), do: nil
  defp non_empty(value), do: value

  defp build_filter_opts(assigns) do
    filters =
      []
      |> maybe_add_filter(:method, assigns.method_filter)
      |> maybe_add_filter(:status, status_range(assigns.status_filter))
      |> maybe_add_filter(:subdomain, assigns.subdomain_filter)
      |> maybe_add_filter(:path_pattern, non_empty(assigns.path_filter))

    if assigns.admin_mode or assigns.subdomain_filter do
      filters
    else
      [{:subdomains_in, assigns.user_subdomains} | filters]
    end
  end

  defp maybe_add_filter(filters, _key, nil), do: filters
  defp maybe_add_filter(filters, key, value), do: [{key, value} | filters]

  defp status_range("2xx"), do: Enum.to_list(200..299)
  defp status_range("3xx"), do: Enum.to_list(300..399)
  defp status_range("4xx"), do: Enum.to_list(400..499)
  defp status_range("5xx"), do: Enum.to_list(500..599)
  defp status_range(_), do: nil

  defp matches_filters?(request, assigns) do
    subdomain_allowed =
      assigns.admin_mode or
        assigns.subdomain_filter != nil or
        request.subdomain in assigns.user_subdomains

    subdomain_allowed and
      (is_nil(assigns.method_filter) or request.method == assigns.method_filter) and
      (is_nil(assigns.status_filter) or request.status in status_range(assigns.status_filter)) and
      (is_nil(assigns.subdomain_filter) or request.subdomain == assigns.subdomain_filter) and
      (assigns.path_filter == "" or path_matches?(request.path, assigns.path_filter))
  end

  defp path_matches?(nil, _pattern), do: false

  defp path_matches?(path, pattern) do
    case Regex.compile(pattern) do
      {:ok, regex} -> Regex.match?(regex, path)
      _ -> true
    end
  end
end
