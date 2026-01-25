defmodule Burrow.Server.Web.AccountLive.Index do
  @moduledoc """
  LiveView for account management.

  Displays and manages:
  - Passkeys (WebAuthn credentials)
  - API tokens
  - Subdomain reservations
  """

  use Phoenix.LiveView

  alias Burrow.Accounts
  alias Burrow.WebAuthn

  @impl true
  def mount(_params, session, socket) do
    case session["current_user"] do
      %{id: user_id} = current_user ->
        case Accounts.get_user(user_id) do
          nil ->
            {:ok, push_navigate(socket, to: "/auth/login")}

          user ->
            {:ok,
             socket
             |> assign(:page_title, "Account")
             |> assign(:current_user, current_user)
             |> assign(:user, user)
             |> load_data()
             |> assign(:challenge, nil)
             |> assign(:show_token, nil)
             |> assign(:error, nil)
             |> assign(:success, nil)}
        end

      _ ->
        {:ok, push_navigate(socket, to: "/auth/login")}
    end
  end

  defp load_data(socket) do
    user_id = socket.assigns.user.id

    socket
    |> assign(:credentials, Accounts.list_credentials(user_id))
    |> assign(:tokens, Accounts.list_api_tokens(user_id))
    |> assign(:reservations, Accounts.list_reservations(user_id))
  end

  @impl true
  def handle_event("add_passkey", _params, socket) do
    user = socket.assigns.user
    existing_ids = Accounts.list_credential_ids(user.id)
    {challenge, options} = WebAuthn.registration_challenge(user, existing_ids)

    {:noreply,
     socket
     |> assign(:challenge, challenge)
     |> push_event("webauthn:register", %{options: options})}
  end

  @impl true
  def handle_event("webauthn_response", %{"response" => response}, socket) do
    case WebAuthn.verify_registration(response, socket.assigns.challenge) do
      {:ok, credential_data} ->
        case Accounts.create_credential(socket.assigns.current_user.id, %{
               credential_id: credential_data.credential_id,
               cose_key: credential_data.cose_key,
               sign_count: credential_data.sign_count,
               friendly_name: "Passkey #{length(socket.assigns.credentials) + 1}"
             }) do
          {:ok, _credential} ->
            {:noreply,
             socket
             |> assign(:challenge, nil)
             |> assign(:success, "Passkey added successfully")
             |> load_data()}

          {:error, _changeset} ->
            {:noreply,
             socket
             |> assign(:challenge, nil)
             |> assign(:error, "Failed to save passkey")}
        end

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:challenge, nil)
         |> assign(:error, "Failed to verify passkey: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("webauthn_error", %{"error" => error}, socket) do
    {:noreply,
     socket
     |> assign(:challenge, nil)
     |> assign(:error, "Passkey error: #{error}")}
  end

  @impl true
  def handle_event("delete_credential", %{"id" => id}, socket) do
    credential = Accounts.get_credential(id)

    cond do
      is_nil(credential) ->
        {:noreply, assign(socket, :error, "Credential not found")}

      credential.user_id != socket.assigns.current_user.id ->
        {:noreply, assign(socket, :error, "Not authorized")}

      Accounts.credential_count(socket.assigns.current_user.id) <= 1 ->
        {:noreply, assign(socket, :error, "Cannot delete your only passkey")}

      true ->
        case Accounts.delete_credential(credential) do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign(:success, "Passkey deleted")
             |> load_data()}

          {:error, _} ->
            {:noreply, assign(socket, :error, "Failed to delete passkey")}
        end
    end
  end

  @impl true
  def handle_event("create_token", %{"name" => name}, socket) do
    case Accounts.create_api_token(socket.assigns.current_user.id, %{name: name}) do
      {:ok, _token, token_string} ->
        {:noreply,
         socket
         |> assign(:show_token, token_string)
         |> assign(:success, "Token created")
         |> load_data()}

      {:error, _changeset} ->
        {:noreply, assign(socket, :error, "Failed to create token")}
    end
  end

  @impl true
  def handle_event("dismiss_token", _params, socket) do
    {:noreply, assign(socket, :show_token, nil)}
  end

  @impl true
  def handle_event("delete_token", %{"id" => id}, socket) do
    case Accounts.delete_api_token_by_id(socket.assigns.current_user.id, id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:success, "Token deleted")
         |> load_data()}

      {:error, _} ->
        {:noreply, assign(socket, :error, "Failed to delete token")}
    end
  end

  @impl true
  def handle_event("release_subdomain", %{"subdomain" => subdomain}, socket) do
    case Accounts.release_subdomain(socket.assigns.current_user.id, subdomain) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:success, "Subdomain #{subdomain} released")
         |> load_data()}

      {:error, _} ->
        {:noreply, assign(socket, :error, "Failed to release subdomain")}
    end
  end

  @impl true
  def handle_event("dismiss_message", _params, socket) do
    {:noreply,
     socket
     |> assign(:error, nil)
     |> assign(:success, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="account-page" id="account-index" phx-hook="WebAuthn">
      <div class="account-header">
        <h1>Account Settings</h1>
        <p>Manage your passkeys, API tokens, and subdomains</p>
      </div>

      <%= if @error do %>
        <div class="alert alert-error" phx-click="dismiss_message">
          <%= @error %>
        </div>
      <% end %>

      <%= if @success do %>
        <div class="alert alert-success" phx-click="dismiss_message">
          <%= @success %>
        </div>
      <% end %>

      <%= if @show_token do %>
        <div class="token-reveal">
          <div class="token-reveal-header">
            <h3>Your New API Token</h3>
            <p>Copy this token now. It won't be shown again.</p>
          </div>
          <div class="token-value">
            <code><%= @show_token %></code>
          </div>
          <div class="token-hint">
            <p>Add to ~/.burrow/config.toml:</p>
            <code>[auth]<br/>token = "<%= @show_token %>"</code>
          </div>
          <button type="button" class="btn btn-primary" phx-click="dismiss_token">
            I've Copied the Token
          </button>
        </div>
      <% end %>

      <!-- Passkeys Section -->
      <div class="section">
        <div class="section-header">
          <h2>Passkeys</h2>
          <button type="button" class="btn btn-sm" phx-click="add_passkey">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="14" height="14">
              <line x1="12" y1="5" x2="12" y2="19"/>
              <line x1="5" y1="12" x2="19" y2="12"/>
            </svg>
            Add Passkey
          </button>
        </div>
        <div class="section-content">
          <%= if @credentials == [] do %>
            <p class="empty-state">No passkeys configured</p>
          <% else %>
            <div class="list">
              <%= for credential <- @credentials do %>
                <div class="list-item">
                  <div class="list-item-icon">
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                      <rect x="3" y="11" width="18" height="11" rx="2" ry="2"/>
                      <path d="M7 11V7a5 5 0 0 1 10 0v4"/>
                    </svg>
                  </div>
                  <div class="list-item-content">
                    <span class="list-item-title"><%= credential.friendly_name || "Passkey" %></span>
                    <span class="list-item-subtitle">
                      Added <local-time utc={DateTime.to_iso8601(credential.inserted_at)} format="full"></local-time>
                    </span>
                  </div>
                  <button
                    type="button"
                    class="btn btn-sm btn-danger"
                    phx-click="delete_credential"
                    phx-value-id={credential.id}
                    data-confirm="Delete this passkey?"
                  >
                    Delete
                  </button>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>

      <!-- API Tokens Section -->
      <div class="section">
        <div class="section-header">
          <h2>API Tokens</h2>
        </div>
        <div class="section-content">
          <form phx-submit="create_token" class="token-form">
            <input type="text" name="name" placeholder="Token name (e.g., laptop, ci)" required />
            <button type="submit" class="btn btn-sm">Create Token</button>
          </form>
          <%= if @tokens == [] do %>
            <p class="empty-state">No API tokens</p>
          <% else %>
            <div class="list">
              <%= for token <- @tokens do %>
                <div class="list-item">
                  <div class="list-item-icon">
                    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                      <rect x="3" y="11" width="18" height="11" rx="2" ry="2"/>
                      <path d="M7 11V7a5 5 0 0 1 10 0v4"/>
                    </svg>
                  </div>
                  <div class="list-item-content">
                    <span class="list-item-title"><%= token.name %></span>
                    <span class="list-item-subtitle">
                      Created <local-time utc={DateTime.to_iso8601(token.inserted_at)} format="full"></local-time>
                      <%= if token.last_used_at do %>
                        · Last used <local-time utc={DateTime.to_iso8601(token.last_used_at)} format="full"></local-time>
                      <% end %>
                    </span>
                  </div>
                  <button
                    type="button"
                    class="btn btn-sm btn-danger"
                    phx-click="delete_token"
                    phx-value-id={token.id}
                    data-confirm="Delete this token?"
                  >
                    Delete
                  </button>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>

      <!-- Subdomains Section -->
      <div class="section">
        <div class="section-header">
          <h2>Reserved Subdomains</h2>
        </div>
        <div class="section-content">
          <%= if @reservations == [] do %>
            <p class="empty-state">No subdomains reserved. Subdomains are automatically reserved when you first use them.</p>
          <% else %>
            <div class="list">
              <%= for reservation <- @reservations do %>
                <div class="list-item">
                  <div class="list-item-content">
                    <span class="list-item-title subdomain"><%= reservation.subdomain %></span>
                    <span class="list-item-subtitle">
                      Reserved <local-time utc={DateTime.to_iso8601(reservation.inserted_at)} format="full"></local-time>
                    </span>
                  </div>
                  <button
                    type="button"
                    class="btn btn-sm btn-danger"
                    phx-click="release_subdomain"
                    phx-value-subdomain={reservation.subdomain}
                    data-confirm="Release subdomain '#{reservation.subdomain}'? Someone else could claim it."
                  >
                    Release
                  </button>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    </div>

    <style>
      .account-page {
        max-width: 800px;
        margin: 0 auto;
      }

      .account-header {
        margin-bottom: 2rem;
      }

      .account-header h1 {
        font-size: 1.5rem;
        font-weight: 600;
        margin-bottom: 0.5rem;
      }

      .account-header p {
        color: var(--text-muted);
        font-size: 0.875rem;
      }

      .alert {
        padding: 0.75rem 1rem;
        border-radius: 8px;
        margin-bottom: 1rem;
        cursor: pointer;
        font-size: 0.875rem;
      }

      .alert-error {
        background: var(--error-bg);
        color: var(--error);
      }

      .alert-success {
        background: var(--success-bg);
        color: var(--success);
      }

      .token-reveal {
        background: var(--bg-surface);
        border: 2px solid var(--accent);
        border-radius: 12px;
        padding: 1.5rem;
        margin-bottom: 1.5rem;
        text-align: center;
      }

      .token-reveal-header h3 {
        margin-bottom: 0.25rem;
      }

      .token-reveal-header p {
        color: var(--text-muted);
        font-size: 0.875rem;
        margin-bottom: 1rem;
      }

      .token-value {
        background: var(--bg-deep);
        padding: 1rem;
        border-radius: 8px;
        margin-bottom: 1rem;
        word-break: break-all;
      }

      .token-value code {
        font-family: 'JetBrains Mono', monospace;
        font-size: 0.875rem;
        color: var(--accent);
      }

      .token-hint {
        background: var(--bg-elevated);
        padding: 1rem;
        border-radius: 8px;
        margin-bottom: 1rem;
        text-align: left;
      }

      .token-hint p {
        font-size: 0.75rem;
        color: var(--text-muted);
        margin-bottom: 0.5rem;
      }

      .token-hint code {
        font-family: 'JetBrains Mono', monospace;
        font-size: 0.75rem;
        color: var(--text-secondary);
      }

      .section {
        background: var(--bg-surface);
        border: 1px solid var(--border);
        border-radius: 12px;
        margin-bottom: 1.5rem;
        overflow: hidden;
      }

      .section-header {
        display: flex;
        justify-content: space-between;
        align-items: center;
        padding: 1rem 1.25rem;
        border-bottom: 1px solid var(--border);
      }

      .section-header h2 {
        font-size: 1rem;
        font-weight: 600;
      }

      .section-content {
        padding: 1rem 1.25rem;
      }

      .token-form {
        display: flex;
        gap: 0.5rem;
        margin-bottom: 1rem;
      }

      .token-form input {
        flex: 1;
      }

      .empty-state {
        color: var(--text-muted);
        font-size: 0.875rem;
        text-align: center;
        padding: 1rem;
      }

      .list {
        display: flex;
        flex-direction: column;
        gap: 0.5rem;
      }

      .list-item {
        display: flex;
        align-items: center;
        gap: 1rem;
        padding: 0.75rem;
        background: var(--bg-elevated);
        border-radius: 8px;
      }

      .list-item-icon {
        width: 36px;
        height: 36px;
        display: flex;
        align-items: center;
        justify-content: center;
        background: var(--bg-surface);
        border-radius: 8px;
        color: var(--text-secondary);
      }

      .list-item-icon svg {
        width: 18px;
        height: 18px;
      }

      .list-item-content {
        flex: 1;
        min-width: 0;
      }

      .list-item-title {
        display: block;
        font-weight: 500;
        margin-bottom: 0.125rem;
      }

      .list-item-title.subdomain {
        font-family: 'JetBrains Mono', monospace;
        color: var(--accent);
      }

      .list-item-subtitle {
        display: block;
        font-size: 0.75rem;
        color: var(--text-muted);
      }

      .btn-danger {
        color: var(--error);
        border-color: var(--error);
      }

      .btn-danger:hover {
        background: var(--error-bg);
      }
    </style>
    """
  end
end
