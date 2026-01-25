defmodule Burrow.Server.Web.AuthLive.Login do
  @moduledoc """
  LiveView for WebAuthn login.

  Supports both:
  - Discoverable credentials (passkey autofill)
  - Username-based login (enter username, then authenticate)
  """

  use Phoenix.LiveView

  alias Burrow.Accounts
  alias Burrow.WebAuthn

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Sign In")
     |> assign(:current_user, session["current_user"])
     |> assign(:username, "")
     |> assign(:error, nil)
     |> assign(:challenge, nil)
     |> assign(:step, :username)}
  end

  @impl true
  def handle_event("username_submit", %{"username" => username}, socket) do
    username = String.trim(username)

    case Accounts.get_user_by_username(username) do
      nil ->
        {:noreply, assign(socket, :error, "User not found. Need an account?")}

      user ->
        {challenge, options} = WebAuthn.authentication_challenge(user)

        {:noreply,
         socket
         |> assign(:username, username)
         |> assign(:challenge, challenge)
         |> assign(:error, nil)
         |> assign(:step, :authenticate)
         |> push_event("webauthn:authenticate", %{options: options})}
    end
  end

  @impl true
  def handle_event("webauthn_response", %{"response" => response}, socket) do
    case WebAuthn.verify_authentication(response, socket.assigns.challenge) do
      {:ok, credential, new_sign_count} ->
        Accounts.update_credential_sign_count(credential, new_sign_count)
        user = Accounts.get_user!(credential.user_id)

        {:noreply,
         socket
         |> push_event("session:create", %{user_id: user.id})
         |> push_navigate(to: "/inspector")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:error, "Authentication failed: #{inspect(reason)}")
         |> assign(:step, :username)
         |> assign(:challenge, nil)}
    end
  end

  @impl true
  def handle_event("webauthn_error", %{"error" => error}, socket) do
    {:noreply,
     socket
     |> assign(:error, "Authentication error: #{error}")
     |> assign(:step, :username)
     |> assign(:challenge, nil)}
  end

  @impl true
  def handle_event("back_to_username", _params, socket) do
    {:noreply,
     socket
     |> assign(:step, :username)
     |> assign(:challenge, nil)
     |> assign(:error, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="auth-page" id="auth-login" phx-hook="WebAuthn">
      <div class="auth-card">
        <div class="auth-header">
          <h1>Sign In</h1>
          <p>Use your passkey to sign in</p>
        </div>

        <%= if @error do %>
          <div class="auth-error">
            <%= @error %>
          </div>
        <% end %>

        <%= if @step == :username do %>
          <form phx-submit="username_submit" class="auth-form">
            <div class="form-group">
              <label for="username">Username</label>
              <input
                type="text"
                id="username"
                name="username"
                value={@username}
                placeholder="your-username"
                autocomplete="username webauthn"
                autofocus
                required
              />
            </div>
            <button type="submit" class="btn btn-primary btn-block">
              Continue
            </button>
          </form>
        <% else %>
          <div class="auth-waiting">
            <div class="passkey-icon">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <rect x="3" y="11" width="18" height="11" rx="2" ry="2"/>
                <path d="M7 11V7a5 5 0 0 1 10 0v4"/>
              </svg>
            </div>
            <p>Waiting for passkey...</p>
            <p class="auth-hint">Complete authentication on your device</p>
            <button type="button" class="btn btn-link" phx-click="back_to_username">
              Cancel
            </button>
          </div>
        <% end %>

        <div class="auth-footer">
          <p>Don't have an account? <a href="/auth/register">Create one</a></p>
        </div>
      </div>
    </div>

    <style>
      .auth-page {
        display: flex;
        justify-content: center;
        align-items: center;
        min-height: calc(100vh - 200px);
      }

      .auth-card {
        background: var(--bg-surface);
        border: 1px solid var(--border);
        border-radius: 16px;
        padding: 2rem;
        width: 100%;
        max-width: 400px;
      }

      .auth-header {
        text-align: center;
        margin-bottom: 2rem;
      }

      .auth-header h1 {
        font-size: 1.5rem;
        font-weight: 600;
        margin-bottom: 0.5rem;
      }

      .auth-header p {
        color: var(--text-muted);
        font-size: 0.875rem;
      }

      .auth-error {
        background: var(--error-bg);
        color: var(--error);
        padding: 0.75rem 1rem;
        border-radius: 8px;
        margin-bottom: 1rem;
        font-size: 0.875rem;
      }

      .auth-form {
        display: flex;
        flex-direction: column;
        gap: 1rem;
      }

      .form-group {
        display: flex;
        flex-direction: column;
        gap: 0.5rem;
      }

      .form-group label {
        font-size: 0.875rem;
        font-weight: 500;
        color: var(--text-secondary);
      }

      .form-group input {
        padding: 0.75rem 1rem;
        font-size: 1rem;
      }

      .btn-block {
        width: 100%;
        padding: 0.75rem;
        font-size: 1rem;
      }

      .btn-link {
        background: transparent;
        border: none;
        color: var(--text-muted);
        cursor: pointer;
        font-size: 0.875rem;
        text-decoration: underline;
        padding: 0;
      }

      .btn-link:hover {
        color: var(--text-secondary);
      }

      .auth-waiting {
        text-align: center;
        padding: 2rem 0;
      }

      .passkey-icon {
        width: 64px;
        height: 64px;
        margin: 0 auto 1rem;
        color: var(--accent);
        animation: pulse 2s ease-in-out infinite;
      }

      .passkey-icon svg {
        width: 100%;
        height: 100%;
      }

      .auth-hint {
        color: var(--text-muted);
        font-size: 0.875rem;
        margin-top: 0.5rem;
      }

      .auth-footer {
        text-align: center;
        margin-top: 2rem;
        padding-top: 1rem;
        border-top: 1px solid var(--border);
      }

      .auth-footer p {
        color: var(--text-muted);
        font-size: 0.875rem;
      }

      .auth-footer a {
        color: var(--accent);
      }
    </style>
    """
  end
end
