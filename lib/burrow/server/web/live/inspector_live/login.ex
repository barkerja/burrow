defmodule Burrow.Server.Web.InspectorLive.Login do
  @moduledoc """
  Login page for the request inspector.
  """

  use Phoenix.LiveView

  @impl true
  def mount(_params, session, socket) do
    case session["current_user"] do
      nil ->
        {:ok, socket}

      _user ->
        {:ok, push_navigate(socket, to: "/inspector")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="login-container">
      <div class="login-card">
        <div class="login-icon">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
            <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>
          </svg>
        </div>

        <h1 class="login-title">Sign in to Inspector</h1>

        <p class="login-description">
          The request inspector requires authentication to view traffic flowing through your tunnels.
        </p>

        <a href="/auth/github" class="github-btn">
          <svg viewBox="0 0 24 24" fill="currentColor">
            <path d="M12 2C6.477 2 2 6.477 2 12c0 4.42 2.87 8.17 6.84 9.5.5.08.66-.23.66-.5v-1.69c-2.77.6-3.36-1.34-3.36-1.34-.46-1.16-1.11-1.47-1.11-1.47-.91-.62.07-.6.07-.6 1 .07 1.53 1.03 1.53 1.03.87 1.52 2.34 1.07 2.91.83.09-.65.35-1.09.63-1.34-2.22-.25-4.55-1.11-4.55-4.92 0-1.11.38-2 1.03-2.71-.1-.25-.45-1.29.1-2.64 0 0 .84-.27 2.75 1.02.79-.22 1.65-.33 2.5-.33.85 0 1.71.11 2.5.33 1.91-1.29 2.75-1.02 2.75-1.02.55 1.35.2 2.39.1 2.64.65.71 1.03 1.6 1.03 2.71 0 3.82-2.34 4.66-4.57 4.91.36.31.69.92.69 1.85V21c0 .27.16.59.67.5C19.14 20.16 22 16.42 22 12A10 10 0 0012 2z"/>
          </svg>
          Sign in with GitHub
        </a>

        <p class="login-notice">
          Access is restricted to authorized users only.
        </p>
      </div>
    </div>

    <style>
      .login-container {
        display: flex;
        align-items: center;
        justify-content: center;
        min-height: calc(100vh - 200px);
        padding: 2rem;
      }

      .login-card {
        background: var(--bg-surface);
        border: 1px solid var(--border);
        border-radius: 16px;
        padding: 2.5rem;
        max-width: 400px;
        width: 100%;
        text-align: center;
      }

      .login-icon {
        width: 56px;
        height: 56px;
        margin: 0 auto 1.5rem;
        background: var(--accent-subtle);
        border-radius: 12px;
        display: flex;
        align-items: center;
        justify-content: center;
      }

      .login-icon svg {
        width: 28px;
        height: 28px;
        color: var(--accent);
      }

      .login-title {
        font-family: 'JetBrains Mono', monospace;
        font-size: 1.25rem;
        font-weight: 600;
        margin-bottom: 0.75rem;
        background: linear-gradient(135deg, var(--text-primary) 0%, var(--text-secondary) 100%);
        -webkit-background-clip: text;
        -webkit-text-fill-color: transparent;
        background-clip: text;
      }

      .login-description {
        color: var(--text-secondary);
        font-size: 0.9rem;
        line-height: 1.6;
        margin-bottom: 2rem;
      }

      .github-btn {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        gap: 0.75rem;
        width: 100%;
        padding: 0.875rem 1.5rem;
        background: var(--bg-elevated);
        border: 1px solid var(--border);
        border-radius: 10px;
        color: var(--text-primary);
        font-family: 'Outfit', sans-serif;
        font-size: 0.95rem;
        font-weight: 500;
        text-decoration: none;
        transition: all 0.2s ease;
      }

      .github-btn:hover {
        background: var(--bg-hover);
        border-color: var(--accent);
        box-shadow: 0 0 20px var(--accent-glow);
        transform: translateY(-1px);
        text-decoration: none;
        color: var(--text-primary);
      }

      .github-btn svg {
        width: 20px;
        height: 20px;
      }

      .login-notice {
        color: var(--text-muted);
        font-size: 0.8rem;
        margin-top: 1.5rem;
      }
    </style>
    """
  end
end
