defmodule Burrow.Server.ErrorPage do
  @moduledoc """
  Generates beautiful HTML error pages for tunnel errors.

  Provides a consistent, branded error experience with:
  - Modern, dark-themed design
  - Tunnel/underground aesthetic
  - Clear error messaging
  - Subtle animations
  """

  import Plug.Conn

  @doc """
  Renders an error page and sends the response.
  """
  def render(conn, status, opts \\ []) do
    {title, message, hint} = error_content(status, opts)

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(status, build_html(status, title, message, hint))
  end

  defp error_content(404, opts) do
    subdomain = Keyword.get(opts, :subdomain)

    if subdomain do
      {
        "Tunnel Not Found",
        "The tunnel \"#{subdomain}\" doesn't exist or has disconnected.",
        "Make sure your burrow client is running and connected."
      }
    else
      {
        "Not Found",
        "The requested resource could not be found.",
        "Check the URL and try again."
      }
    end
  end

  defp error_content(413, opts) do
    max_size = Keyword.get(opts, :max_size, 10_485_760)
    max_mb = Float.round(max_size / 1_048_576, 1)

    {
      "Request Too Large",
      "The request body exceeds the maximum allowed size of #{max_mb} MB.",
      "Try sending a smaller payload or splitting it into multiple requests."
    }
  end

  defp error_content(502, opts) do
    reason = Keyword.get(opts, :reason, "unknown error")

    {
      "Bad Gateway",
      "The tunnel client returned an invalid response.",
      "Error: #{reason}"
    }
  end

  defp error_content(504, opts) do
    context = Keyword.get(opts, :context, :request)

    case context do
      :websocket ->
        {
          "WebSocket Timeout",
          "The tunnel client didn't respond to the WebSocket upgrade in time.",
          "The local service may be unavailable or slow to respond."
        }

      _ ->
        {
          "Gateway Timeout",
          "The tunnel client didn't respond in time.",
          "The local service may be unavailable or slow to respond."
        }
    end
  end

  defp error_content(status, _opts) do
    {
      "Error #{status}",
      "An unexpected error occurred.",
      "Please try again later."
    }
  end

  defp build_html(status, title, message, hint) do
    base_domain = Application.get_env(:burrow, :server, [])[:base_domain] || "localhost"
    logo_url = "https://#{base_domain}/images/burrow_tunnel_logo.png"

    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>#{title} · Burrow</title>
      <style>
        @import url('https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500;600&family=Outfit:wght@300;400;500;600&display=swap');

        *, *::before, *::after {
          box-sizing: border-box;
          margin: 0;
          padding: 0;
        }

        :root {
          --bg-deep: #0a0a0b;
          --bg-surface: #131316;
          --bg-elevated: #1a1a1f;
          --border: #2a2a32;
          --text-primary: #f0f0f2;
          --text-secondary: #8b8b96;
          --text-muted: #5c5c66;
          --accent: #7c5cff;
          --accent-glow: rgba(124, 92, 255, 0.4);
          --warning: #ff6b4a;
          --tunnel-dark: #0d0d0f;
          --tunnel-ring: #1f1f24;
        }

        html {
          font-size: 16px;
          -webkit-font-smoothing: antialiased;
          -moz-osx-font-smoothing: grayscale;
        }

        body {
          font-family: 'Outfit', -apple-system, BlinkMacSystemFont, sans-serif;
          background: var(--bg-deep);
          color: var(--text-primary);
          min-height: 100vh;
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          padding: 2rem;
          position: relative;
          overflow: hidden;
        }

        /* Animated background tunnel effect */
        .tunnel-bg {
          position: fixed;
          inset: 0;
          display: flex;
          align-items: center;
          justify-content: center;
          pointer-events: none;
          z-index: 0;
        }

        .tunnel-ring {
          position: absolute;
          border: 1px solid var(--tunnel-ring);
          border-radius: 50%;
          opacity: 0;
          animation: tunnel-pulse 4s ease-out infinite;
        }

        .tunnel-ring:nth-child(1) { width: 200px; height: 200px; animation-delay: 0s; }
        .tunnel-ring:nth-child(2) { width: 350px; height: 350px; animation-delay: 0.5s; }
        .tunnel-ring:nth-child(3) { width: 500px; height: 500px; animation-delay: 1s; }
        .tunnel-ring:nth-child(4) { width: 650px; height: 650px; animation-delay: 1.5s; }
        .tunnel-ring:nth-child(5) { width: 800px; height: 800px; animation-delay: 2s; }
        .tunnel-ring:nth-child(6) { width: 950px; height: 950px; animation-delay: 2.5s; }

        @keyframes tunnel-pulse {
          0% {
            opacity: 0.5;
            transform: scale(0.8);
          }
          100% {
            opacity: 0;
            transform: scale(1.2);
          }
        }

        /* Main content */
        .container {
          position: relative;
          z-index: 1;
          max-width: 480px;
          width: 100%;
          text-align: center;
        }

        /* Logo */
        .logo {
          margin-bottom: 0.5rem;
          animation: fade-in 0.6s ease-out;
        }

        .logo img {
          width: 400px;
          height: 400px;
          object-fit: contain;
          filter: drop-shadow(0 0 40px var(--accent-glow));
        }

        /* Status code */
        .status-code {
          font-family: 'JetBrains Mono', monospace;
          font-size: 5rem;
          font-weight: 600;
          line-height: 1;
          background: linear-gradient(135deg, var(--text-primary) 0%, var(--text-secondary) 100%);
          -webkit-background-clip: text;
          -webkit-text-fill-color: transparent;
          background-clip: text;
          margin-bottom: 1rem;
          animation: fade-in 0.6s ease-out 0.1s backwards;
        }

        /* Title */
        .title {
          font-size: 1.5rem;
          font-weight: 500;
          color: var(--text-primary);
          margin-bottom: 1rem;
          animation: fade-in 0.6s ease-out 0.2s backwards;
        }

        /* Message */
        .message {
          font-size: 1rem;
          font-weight: 400;
          color: var(--text-secondary);
          line-height: 1.6;
          margin-bottom: 1.5rem;
          animation: fade-in 0.6s ease-out 0.3s backwards;
        }

        /* Hint box */
        .hint {
          background: var(--bg-surface);
          border: 1px solid var(--border);
          border-radius: 12px;
          padding: 1rem 1.25rem;
          font-size: 0.875rem;
          color: var(--text-muted);
          line-height: 1.5;
          animation: fade-in 0.6s ease-out 0.4s backwards;
        }

        .hint::before {
          content: '💡';
          margin-right: 0.5rem;
        }

        /* Footer */
        .footer {
          margin-top: 3rem;
          animation: fade-in 0.6s ease-out 0.5s backwards;
        }

        .footer a {
          display: inline-flex;
          align-items: center;
          gap: 0.5rem;
          font-size: 0.875rem;
          color: var(--text-muted);
          text-decoration: none;
          transition: color 0.2s ease;
        }

        .footer a:hover {
          color: var(--accent);
        }

        .footer svg {
          width: 16px;
          height: 16px;
        }

        @keyframes fade-in {
          from {
            opacity: 0;
            transform: translateY(10px);
          }
          to {
            opacity: 1;
            transform: translateY(0);
          }
        }

        /* Responsive */
        @media (max-width: 480px) {
          .logo img {
            width: 280px;
            height: 280px;
          }

          .status-code {
            font-size: 4rem;
          }

          .title {
            font-size: 1.25rem;
          }
        }
      </style>
    </head>
    <body>
      <!-- Animated tunnel background -->
      <div class="tunnel-bg">
        <div class="tunnel-ring"></div>
        <div class="tunnel-ring"></div>
        <div class="tunnel-ring"></div>
        <div class="tunnel-ring"></div>
        <div class="tunnel-ring"></div>
        <div class="tunnel-ring"></div>
      </div>

      <div class="container">
        <!-- Logo -->
        <div class="logo">
          <img src="#{logo_url}" alt="Burrow" />
        </div>

        <!-- Status code -->
        <div class="status-code">#{status}</div>

        <!-- Title -->
        <h1 class="title">#{escape_html(title)}</h1>

        <!-- Message -->
        <p class="message">#{escape_html(message)}</p>

        <!-- Hint -->
        <div class="hint">#{escape_html(hint)}</div>

        <!-- Footer -->
        <div class="footer">
          <a href="https://github.com/barkerja/burrow" target="_blank" rel="noopener">
            <svg viewBox="0 0 24 24" fill="currentColor">
              <path d="M12 2C6.477 2 2 6.477 2 12c0 4.42 2.87 8.17 6.84 9.5.5.08.66-.23.66-.5v-1.69c-2.77.6-3.36-1.34-3.36-1.34-.46-1.16-1.11-1.47-1.11-1.47-.91-.62.07-.6.07-.6 1 .07 1.53 1.03 1.53 1.03.87 1.52 2.34 1.07 2.91.83.09-.65.35-1.09.63-1.34-2.22-.25-4.55-1.11-4.55-4.92 0-1.11.38-2 1.03-2.71-.1-.25-.45-1.29.1-2.64 0 0 .84-.27 2.75 1.02.79-.22 1.65-.33 2.5-.33.85 0 1.71.11 2.5.33 1.91-1.29 2.75-1.02 2.75-1.02.55 1.35.2 2.39.1 2.64.65.71 1.03 1.6 1.03 2.71 0 3.82-2.34 4.66-4.57 4.91.36.31.69.92.69 1.85V21c0 .27.16.59.67.5C19.14 20.16 22 16.42 22 12A10 10 0 0012 2z"/>
            </svg>
            Powered by Burrow
          </a>
        </div>
      </div>
    </body>
    </html>
    """
  end

  defp escape_html(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end

  defp escape_html(text), do: escape_html(to_string(text))
end
