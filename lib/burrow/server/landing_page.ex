defmodule Burrow.Server.LandingPage do
  @moduledoc """
  Generates the landing page for Burrow.

  Matches the design aesthetic of error pages with:
  - Modern, dark-themed design
  - Tunnel/underground aesthetic
  - Animated background
  - GitHub login button
  """

  import Plug.Conn

  @doc """
  Renders the landing page.
  """
  def render(conn) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, build_html())
  end

  defp build_html do
    base_domain = Application.get_env(:burrow, :server, [])[:base_domain] || "localhost"
    logo_url = "https://#{base_domain}/images/burrow_tunnel_logo.png"

    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Burrow · Expose local services to the internet</title>
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
          --accent-hover: #6a4de6;
          --accent-glow: rgba(124, 92, 255, 0.4);
          --tunnel-ring: #1f1f24;
        }

        html, body {
          height: 100%;
          overflow: hidden;
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
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          padding: 1rem;
          position: relative;
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
          margin-bottom: 0;
          animation: fade-in 0.6s ease-out;
        }

        .logo img {
          width: 400px;
          height: 400px;
          object-fit: contain;
          filter: drop-shadow(0 0 40px var(--accent-glow));
        }

        /* Brand name */
        .brand {
          font-family: 'JetBrains Mono', monospace;
          font-size: 3rem;
          font-weight: 600;
          letter-spacing: -0.02em;
          background: linear-gradient(135deg, var(--text-primary) 0%, var(--text-secondary) 100%);
          -webkit-background-clip: text;
          -webkit-text-fill-color: transparent;
          background-clip: text;
          margin-bottom: 0.5rem;
          animation: fade-in 0.6s ease-out 0.1s backwards;
        }

        /* Tagline */
        .tagline {
          font-size: 1.125rem;
          font-weight: 400;
          color: var(--text-secondary);
          line-height: 1.6;
          margin-bottom: 1.5rem;
          animation: fade-in 0.6s ease-out 0.2s backwards;
        }

        /* Features */
        .features {
          display: flex;
          justify-content: center;
          gap: 2rem;
          margin-bottom: 1.5rem;
          animation: fade-in 0.6s ease-out 0.3s backwards;
        }

        .feature {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          font-size: 0.875rem;
          color: var(--text-muted);
        }

        .feature svg {
          width: 16px;
          height: 16px;
          color: var(--accent);
        }

        /* Login button */
        .login-btn {
          display: inline-flex;
          align-items: center;
          justify-content: center;
          gap: 0.75rem;
          background: var(--bg-surface);
          border: 1px solid var(--border);
          border-radius: 12px;
          padding: 1rem 2rem;
          font-family: 'Outfit', sans-serif;
          font-size: 1rem;
          font-weight: 500;
          color: var(--text-primary);
          text-decoration: none;
          cursor: pointer;
          transition: all 0.2s ease;
          animation: fade-in 0.6s ease-out 0.4s backwards;
        }

        .login-btn:hover {
          background: var(--bg-elevated);
          border-color: var(--accent);
          box-shadow: 0 0 20px var(--accent-glow);
          transform: translateY(-2px);
        }

        .login-btn svg {
          width: 20px;
          height: 20px;
        }

        /* Footer */
        .footer {
          margin-top: 2rem;
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
            width: 160px;
            height: 160px;
          }

          .brand {
            font-size: 1.75rem;
            margin-bottom: 0.25rem;
          }

          .tagline {
            font-size: 0.85rem;
            margin-bottom: 1rem;
          }

          .features {
            gap: 1rem;
            margin-bottom: 1rem;
          }

          .feature {
            font-size: 0.75rem;
          }

          .login-btn {
            padding: 0.75rem 1.5rem;
            font-size: 0.9rem;
          }

          .footer {
            margin-top: 1.5rem;
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

        <!-- Brand -->
        <h1 class="brand">burrow</h1>

        <!-- Tagline -->
        <p class="tagline">Expose your local services to the internet through secure tunnels</p>

        <!-- Features -->
        <div class="features">
          <div class="feature">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>
            </svg>
            Secure
          </div>
          <div class="feature">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <circle cx="12" cy="12" r="10"/>
              <polyline points="12 6 12 12 16 14"/>
            </svg>
            Fast
          </div>
          <div class="feature">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z"/>
            </svg>
            Simple
          </div>
        </div>

        <!-- Login button -->
        <a href="/auth/github" class="login-btn">
          <svg viewBox="0 0 24 24" fill="currentColor">
            <path d="M12 2C6.477 2 2 6.477 2 12c0 4.42 2.87 8.17 6.84 9.5.5.08.66-.23.66-.5v-1.69c-2.77.6-3.36-1.34-3.36-1.34-.46-1.16-1.11-1.47-1.11-1.47-.91-.62.07-.6.07-.6 1 .07 1.53 1.03 1.53 1.03.87 1.52 2.34 1.07 2.91.83.09-.65.35-1.09.63-1.34-2.22-.25-4.55-1.11-4.55-4.92 0-1.11.38-2 1.03-2.71-.1-.25-.45-1.29.1-2.64 0 0 .84-.27 2.75 1.02.79-.22 1.65-.33 2.5-.33.85 0 1.71.11 2.5.33 1.91-1.29 2.75-1.02 2.75-1.02.55 1.35.2 2.39.1 2.64.65.71 1.03 1.6 1.03 2.71 0 3.82-2.34 4.66-4.57 4.91.36.31.69.92.69 1.85V21c0 .27.16.59.67.5C19.14 20.16 22 16.42 22 12A10 10 0 0012 2z"/>
          </svg>
          Sign in with GitHub
        </a>

        <!-- Footer -->
        <div class="footer">
          <a href="https://github.com/barkerja/burrow" target="_blank" rel="noopener">
            <svg viewBox="0 0 24 24" fill="currentColor">
              <path d="M12 2C6.477 2 2 6.477 2 12c0 4.42 2.87 8.17 6.84 9.5.5.08.66-.23.66-.5v-1.69c-2.77.6-3.36-1.34-3.36-1.34-.46-1.16-1.11-1.47-1.11-1.47-.91-.62.07-.6.07-.6 1 .07 1.53 1.03 1.53 1.03.87 1.52 2.34 1.07 2.91.83.09-.65.35-1.09.63-1.34-2.22-.25-4.55-1.11-4.55-4.92 0-1.11.38-2 1.03-2.71-.1-.25-.45-1.29.1-2.64 0 0 .84-.27 2.75 1.02.79-.22 1.65-.33 2.5-.33.85 0 1.71.11 2.5.33 1.91-1.29 2.75-1.02 2.75-1.02.55 1.35.2 2.39.1 2.64.65.71 1.03 1.6 1.03 2.71 0 3.82-2.34 4.66-4.57 4.91.36.31.69.92.69 1.85V21c0 .27.16.59.67.5C19.14 20.16 22 16.42 22 12A10 10 0 0012 2z"/>
            </svg>
            View on GitHub
          </a>
        </div>
      </div>
    </body>
    </html>
    """
  end
end
