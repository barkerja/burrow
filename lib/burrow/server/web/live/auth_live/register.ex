defmodule Burrow.Server.Web.AuthLive.Register do
  @moduledoc """
  LiveView for WebAuthn registration.

  Flow:
  1. User enters username
  2. WebAuthn credential is created
  3. User is logged in
  """

  use Phoenix.LiveView

  alias Burrow.Accounts
  alias Burrow.WebAuthn

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Create Account")
     |> assign(:current_user, session["current_user"])
     |> assign(:username, "")
     |> assign(:error, nil)
     |> assign(:challenge, nil)
     |> assign(:step, :username)}
  end

  @impl true
  def handle_event("username_submit", %{"username" => username}, socket) do
    username = String.trim(String.downcase(username))

    cond do
      String.length(username) < 3 ->
        {:noreply, assign(socket, :error, "Username must be at least 3 characters")}

      String.length(username) > 32 ->
        {:noreply, assign(socket, :error, "Username must be at most 32 characters")}

      not Regex.match?(~r/^[a-z0-9][a-z0-9_-]*[a-z0-9]$|^[a-z0-9]$/, username) ->
        {:noreply,
         assign(
           socket,
           :error,
           "Username must be alphanumeric (a-z, 0-9, -, _), start and end with alphanumeric"
         )}

      Accounts.user_exists?(username) ->
        {:noreply, assign(socket, :error, "Username is already taken")}

      true ->
        {challenge, options} = WebAuthn.registration_challenge(username)

        {:noreply,
         socket
         |> assign(:username, username)
         |> assign(:challenge, challenge)
         |> assign(:error, nil)
         |> assign(:step, :register)
         |> push_event("webauthn:register", %{options: options})}
    end
  end

  @impl true
  def handle_event("webauthn_response", %{"response" => response}, socket) do
    case WebAuthn.verify_registration(response, socket.assigns.challenge) do
      {:ok, credential_data} ->
        case create_user_with_credential(socket.assigns.username, credential_data) do
          {:ok, user} ->
            {:noreply,
             socket
             |> push_event("session:create", %{user_id: user.id})
             |> push_navigate(to: "/inspector")}

          {:error, reason} ->
            {:noreply,
             socket
             |> assign(:error, "Failed to create account: #{inspect(reason)}")
             |> assign(:step, :username)
             |> assign(:challenge, nil)}
        end

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:error, "Registration failed: #{inspect(reason)}")
         |> assign(:step, :username)
         |> assign(:challenge, nil)}
    end
  end

  @impl true
  def handle_event("webauthn_error", %{"error" => error}, socket) do
    {:noreply,
     socket
     |> assign(:error, "Registration error: #{error}")
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

  defp create_user_with_credential(username, credential_data) do
    case Accounts.create_user(%{username: username}) do
      {:ok, user} ->
        case Accounts.create_credential(user.id, %{
               credential_id: credential_data.credential_id,
               cose_key: credential_data.cose_key,
               sign_count: credential_data.sign_count,
               friendly_name: "Default passkey"
             }) do
          {:ok, _credential} -> {:ok, user}
          {:error, changeset} -> {:error, changeset}
        end

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="auth-page" id="auth-register" phx-hook="WebAuthn">
      <div class="auth-card">
        <div class="auth-header">
          <h1>Create Account</h1>
          <p>Set up your account with a passkey</p>
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
                autocomplete="username"
                autofocus
                required
              />
              <span class="form-hint">
                3-32 characters, lowercase letters, numbers, hyphens, underscores
              </span>
            </div>
            <button type="submit" class="btn btn-primary btn-block">
              Continue
            </button>
          </form>
        <% else %>
          <div class="auth-waiting">
            <div class="passkey-icon">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>
              </svg>
            </div>
            <p>Creating passkey...</p>
            <p class="auth-hint">Complete registration on your device</p>
            <button type="button" class="btn btn-link" phx-click="back_to_username">
              Cancel
            </button>
          </div>
        <% end %>

        <div class="auth-footer">
          <p>Already have an account? <a href="/auth/login">Sign in</a></p>
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

      .form-hint {
        font-size: 0.75rem;
        color: var(--text-muted);
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
