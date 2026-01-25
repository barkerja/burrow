defmodule Burrow.Server.Web.InspectorLive.Unauthorized do
  @moduledoc """
  Unauthorized access page for the request inspector.
  """

  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="unauthorized-container">
      <div class="unauthorized-card">
        <div class="unauthorized-icon">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
            <circle cx="12" cy="12" r="10"/>
            <line x1="4.93" y1="4.93" x2="19.07" y2="19.07"/>
          </svg>
        </div>

        <h1 class="unauthorized-title">Access Denied</h1>

        <p class="unauthorized-description">
          You don't have permission to access the request inspector. Access is restricted to authorized users.
        </p>

        <p class="unauthorized-hint">
          If you believe this is an error, please contact the server administrator.
        </p>

        <div class="unauthorized-actions">
          <a href="/auth/logout" class="btn" data-method="post">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="16" height="16">
              <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/>
              <polyline points="16 17 21 12 16 7"/>
              <line x1="21" y1="12" x2="9" y2="12"/>
            </svg>
            Sign Out
          </a>
          <a href="/auth/login" class="btn btn-primary">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="16" height="16">
              <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/>
              <circle cx="9" cy="7" r="4"/>
              <path d="M23 21v-2a4 4 0 0 0-3-3.87"/>
              <path d="M16 3.13a4 4 0 0 1 0 7.75"/>
            </svg>
            Try Different Account
          </a>
        </div>
      </div>
    </div>

    <style>
      .unauthorized-container {
        display: flex;
        align-items: center;
        justify-content: center;
        min-height: calc(100vh - 200px);
        padding: 2rem;
      }

      .unauthorized-card {
        background: var(--bg-surface);
        border: 1px solid var(--border);
        border-radius: 16px;
        padding: 2.5rem;
        max-width: 450px;
        width: 100%;
        text-align: center;
      }

      .unauthorized-icon {
        width: 64px;
        height: 64px;
        margin: 0 auto 1.5rem;
        background: var(--error-bg);
        border-radius: 50%;
        display: flex;
        align-items: center;
        justify-content: center;
      }

      .unauthorized-icon svg {
        width: 32px;
        height: 32px;
        color: var(--error);
      }

      .unauthorized-title {
        font-family: 'JetBrains Mono', monospace;
        font-size: 1.5rem;
        font-weight: 600;
        margin-bottom: 1rem;
        color: var(--error);
      }

      .unauthorized-description {
        color: var(--text-secondary);
        font-size: 0.95rem;
        line-height: 1.6;
        margin-bottom: 1rem;
      }

      .unauthorized-hint {
        color: var(--text-muted);
        font-size: 0.85rem;
        margin-bottom: 2rem;
        padding: 0.75rem 1rem;
        background: var(--bg-elevated);
        border-radius: 8px;
      }

      .unauthorized-actions {
        display: flex;
        gap: 0.75rem;
        justify-content: center;
      }

      .unauthorized-actions .btn {
        flex: 1;
        max-width: 180px;
      }
    </style>
    """
  end
end
