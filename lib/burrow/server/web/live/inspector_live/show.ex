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
    # JavaScript will handle the actual copying
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div style="display: flex; flex-direction: column; flex: 1; min-height: 0;">
      <.link navigate={"/inspector"} class="btn" style="margin-bottom: 1rem; flex-shrink: 0;">
        &larr; Back to requests
      </.link>

      <%= if @request do %>
        <div class="panel" style="margin-bottom: 1rem; flex-shrink: 0;">
          <div class="panel-header">
            <span>
              <span class={"method method-#{String.downcase(@request.method)}"}><%= @request.method %></span>
              <%= @request.subdomain %>.<%= get_base_domain() %><%= @request.path %>
            </span>
            <span class={status_class(@request.status)}>
              <%= @request.status || "Pending" %>
            </span>
          </div>
          <div class="panel-body">
            <div style="display: grid; grid-template-columns: repeat(4, 1fr); gap: 1rem; margin-bottom: 1rem;">
              <div>
                <strong style="color: var(--text-muted);">Started</strong><br/>
                <%= format_datetime(@request.started_at) %>
              </div>
              <div>
                <strong style="color: var(--text-muted);">Duration</strong><br/>
                <%= if @request.duration_ms, do: "#{@request.duration_ms}ms", else: "pending..." %>
              </div>
              <div>
                <strong style="color: var(--text-muted);">Request Size</strong><br/>
                <%= format_bytes(@request.request_size) %>
              </div>
              <div>
                <strong style="color: var(--text-muted);">Response Size</strong><br/>
                <%= format_bytes(@request.response_size) %>
              </div>
            </div>
            <div style="display: grid; grid-template-columns: repeat(4, 1fr); gap: 1rem; margin-bottom: 1rem;">
              <div>
                <strong style="color: var(--text-muted);">Client IP</strong><br/>
                <%= @request.client_ip || "-" %>
                <%= if @request.ip_info && @request.ip_info[:isp] do %>
                  <br/><span style="font-size: 0.8rem; color: var(--text-muted);"><%= @request.ip_info.isp %></span>
                <% end %>
              </div>
              <div>
                <strong style="color: var(--text-muted);">Location</strong><br/>
                <%= format_location(@request.ip_info) %>
              </div>
              <div>
                <strong style="color: var(--text-muted);">Content-Type</strong><br/>
                <span style="font-size: 0.85rem;"><%= @request.content_type || "-" %></span>
              </div>
              <div>
                <strong style="color: var(--text-muted);">Response Type</strong><br/>
                <span style="font-size: 0.85rem;"><%= @request.response_content_type || "-" %></span>
              </div>
            </div>
            <%= if @request.user_agent do %>
              <div style="margin-bottom: 0.5rem;">
                <strong style="color: var(--text-muted);">User-Agent</strong><br/>
                <span style="font-size: 0.85rem; word-break: break-all;"><%= @request.user_agent %></span>
              </div>
            <% end %>
            <%= if @request.referer do %>
              <div>
                <strong style="color: var(--text-muted);">Referer</strong><br/>
                <span style="font-size: 0.85rem; word-break: break-all;"><%= @request.referer %></span>
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
                    <div><strong><%= name %>:</strong> <%= value %></div>
                  <% end %>
                  <%= if (@request.headers || []) == [] do %>
                    <span style="color: var(--text-muted);">No headers</span>
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
                    <span style="color: var(--text-muted);">No body</span>
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
                          <div><strong><%= name %>:</strong> <%= value %></div>
                        <% {name, value} -> %>
                          <div><strong><%= name %>:</strong> <%= value %></div>
                        <% _ -> %>
                      <% end %>
                    <% end %>
                    <%= if @request.response_headers == [] do %>
                      <span style="color: var(--text-muted);">No headers</span>
                    <% end %>
                  <% else %>
                    <span style="color: var(--text-muted);">Awaiting response...</span>
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
                    <span style="color: var(--text-muted);">
                      <%= if @request.status, do: "No body", else: "Awaiting response..." %>
                    </span>
                  <% end %>
                </div>
              </div>
            </div>
          </div>
        </div>

        <div class="panel" style="margin-top: 1rem; flex-shrink: 0;">
          <div class="panel-header">
            <span>cURL Command</span>
            <button class="btn" onclick={"navigator.clipboard.writeText(document.getElementById('curl-cmd').textContent)"}>
              Copy
            </button>
          </div>
          <div class="panel-body" style="padding: 0.5rem 1rem;">
            <div class="code-block" style="max-height: 80px; font-size: 0.75rem;" id="curl-cmd"><%= @curl_command %></div>
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
    """
  end

  # Helper functions

  defp status_class(nil), do: "status status-pending"
  defp status_class(status) when status >= 200 and status < 300, do: "status status-2xx"
  defp status_class(status) when status >= 300 and status < 400, do: "status status-3xx"
  defp status_class(status) when status >= 400 and status < 500, do: "status status-4xx"
  defp status_class(status) when status >= 500, do: "status status-5xx"
  defp status_class(_), do: "status"

  defp format_datetime(nil), do: "-"

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")
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
    # Try to pretty-print JSON
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

    # Build header flags
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
