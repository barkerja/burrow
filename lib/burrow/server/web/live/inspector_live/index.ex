defmodule Burrow.Server.Web.InspectorLive.Index do
  @moduledoc """
  LiveView for the request inspector dashboard.

  Displays real-time HTTP request/response logs flowing through tunnels.
  """

  use Phoenix.LiveView

  alias Burrow.Server.RequestStore

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Burrow.PubSub, RequestStore.pubsub_topic())
    end

    requests = RequestStore.list_requests(limit: 100)
    current_user = session["current_user"]

    {:ok,
     socket
     |> assign(:requests, requests)
     |> assign(:method_filter, nil)
     |> assign(:status_filter, nil)
     |> assign(:path_filter, "")
     |> assign(:request_count, RequestStore.count())
     |> assign(:current_user, current_user)}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
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
    path_filter = params["path"] || ""

    socket =
      socket
      |> assign(:method_filter, method_filter)
      |> assign(:status_filter, status_filter)
      |> assign(:path_filter, path_filter)

    # Re-fetch with filters
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
    <div>
      <div class="filters" style="display: flex; justify-content: space-between; align-items: center;">
        <div style="display: flex; gap: 0.5rem;">
          <form phx-change="filter" phx-submit="filter" style="display: flex; gap: 0.5rem;">
            <select name="method" phx-change="filter">
              <option value="">All Methods</option>
              <option value="GET" selected={@method_filter == "GET"}>GET</option>
              <option value="POST" selected={@method_filter == "POST"}>POST</option>
              <option value="PUT" selected={@method_filter == "PUT"}>PUT</option>
              <option value="PATCH" selected={@method_filter == "PATCH"}>PATCH</option>
              <option value="DELETE" selected={@method_filter == "DELETE"}>DELETE</option>
            </select>
            <select name="status" phx-change="filter">
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
          </form>
          <button class="btn" phx-click="clear">Clear All</button>
        </div>

        <%= if @current_user do %>
          <div style="display: flex; align-items: center; gap: 0.75rem;">
            <span style="color: var(--text-muted); font-size: 0.875rem;">
              <%= @current_user.username %>
            </span>
            <form action="/auth/logout" method="post" style="display: inline;">
              <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
              <button type="submit" class="btn" style="padding: 0.25rem 0.5rem; font-size: 0.75rem;">
                Sign Out
              </button>
            </form>
          </div>
        <% end %>
      </div>

      <div class="panel">
        <div class="panel-header">
          <span><%= @request_count %> total requests</span>
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
                  <td><%= format_time(request.started_at) %></td>
                  <td>
                    <span class={"method method-#{String.downcase(request.method)}"}>
                      <%= request.method %>
                    </span>
                  </td>
                  <td><%= request.subdomain %></td>
                  <td>
                    <.link navigate={"/inspector/requests/#{request.id}"}>
                      <%= truncate(request.path, 50) %>
                    </.link>
                  </td>
                  <td>
                    <span class={status_class(request.status)}>
                      <%= request.status || "..." %>
                    </span>
                  </td>
                  <td>
                    <%= if request.response_size do %>
                      <%= format_bytes(request.response_size) %>
                    <% else %>
                      <span class="status-pending">-</span>
                    <% end %>
                  </td>
                  <td>
                    <%= if request.duration_ms do %>
                      <%= request.duration_ms %>ms
                    <% else %>
                      <span class="status-pending">pending</span>
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
    """
  end

  # Helper functions

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
      if(request.request_size && request.request_size > 0, do: "Req Size: #{format_bytes(request.request_size)}"),
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
  defp matches?(req, :path_pattern, pattern) do
    case Regex.compile(pattern) do
      {:ok, regex} -> Regex.match?(regex, req.path || "")
      _ -> true
    end
  end
  defp matches?(_, _, _), do: true
end
