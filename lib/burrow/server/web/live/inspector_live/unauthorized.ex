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
    <div style="display: flex; flex-direction: column; align-items: center; justify-content: center; min-height: 60vh;">
      <div class="panel" style="max-width: 450px; width: 100%;">
        <div class="panel-header">
          <span style="color: var(--error);">Access Denied</span>
        </div>
        <div class="panel-body" style="text-align: center;">
          <div style="font-size: 3rem; margin-bottom: 1rem;">
            <span style="color: var(--error);">&#128683;</span>
          </div>

          <p style="color: var(--text-muted); margin-bottom: 1rem;">
            You don't have permission to access the request inspector.
          </p>

          <p style="color: var(--text-muted); margin-bottom: 1.5rem; font-size: 0.9rem;">
            Access is restricted to authorized GitHub users and organization members.
            If you believe this is an error, please contact the server administrator.
          </p>

          <div style="display: flex; gap: 1rem; justify-content: center;">
            <a href="/inspector/login" class="btn">
              Try Different Account
            </a>
            <form action="/auth/logout" method="post" style="display: inline;">
              <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
              <button type="submit" class="btn">
                Sign Out
              </button>
            </form>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
