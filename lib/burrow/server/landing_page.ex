defmodule Burrow.Server.LandingPage do
  @moduledoc """
  Generates the landing page for Burrow.

  Modern, dark-themed design with:
  - Zinc-based color palette
  - Perspective grid with animated traversing orbs
  - Clean typography
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
          --bg-deep: #09090b;
          --bg-surface: #18181b;
          --bg-elevated: #27272a;
          --border: #3f3f46;
          --border-subtle: #27272a;
          --text-primary: #fafafa;
          --text-secondary: #a1a1aa;
          --text-muted: #71717a;
          --accent: #a1a1aa;
          --accent-hover: #d4d4d8;
          --grid-line: rgba(80, 80, 90, 0.6);
          --orb-glow: rgba(161, 161, 170, 0.6);
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

        /* Perspective grid background */
        .grid-bg {
          position: fixed;
          bottom: 0;
          left: 0;
          right: 0;
          height: 140vh;
          margin: 0 -150%;
          width: 400%;
          pointer-events: none;
          z-index: 0;
          overflow: hidden;
          transform: perspective(400px) rotateX(45deg);
          transform-origin: center bottom;
        }

        .grid-plane {
          position: absolute;
          inset: 0;
          background-image:
            repeating-linear-gradient(0deg, var(--grid-line), var(--grid-line) 1px, transparent 1px, transparent 40px),
            repeating-linear-gradient(90deg, var(--grid-line), var(--grid-line) 1px, transparent 1px, transparent 40px);
        }

        .grid-bg::after {
          content: '';
          position: absolute;
          top: 0;
          left: 0;
          right: 0;
          height: 40%;
          background: linear-gradient(to bottom, var(--bg-deep) 0%, transparent 100%);
          pointer-events: none;
        }

        /* Orb canvas layers - flat, projection done in JS */
        .orb-canvas {
          position: fixed;
          inset: 0;
          pointer-events: none;
        }

        #canvas-bottom {
          z-index: 1;
        }

        #canvas-top {
          z-index: 2;
          opacity: 0.7;
        }

        /* Main content */
        .container {
          position: relative;
          z-index: 1;
          max-width: 520px;
          width: 100%;
          text-align: center;
        }

        /* Brand name */
        .brand {
          font-family: 'JetBrains Mono', monospace;
          font-size: 4rem;
          font-weight: 600;
          letter-spacing: -0.03em;
          color: var(--text-primary);
          margin-bottom: 1rem;
          animation: fade-in 0.8s ease-out;
        }

        /* Tagline */
        .tagline {
          font-size: 1.25rem;
          font-weight: 400;
          color: var(--text-secondary);
          line-height: 1.6;
          margin-bottom: 2.5rem;
          animation: fade-in 0.8s ease-out 0.15s backwards;
        }

        /* Features */
        .features {
          display: flex;
          justify-content: center;
          gap: 2.5rem;
          margin-bottom: 2.5rem;
          animation: fade-in 0.8s ease-out 0.3s backwards;
        }

        .feature {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          font-size: 0.875rem;
          color: var(--text-muted);
          transition: color 0.2s ease;
        }

        .feature:hover {
          color: var(--text-secondary);
        }

        .feature svg {
          width: 16px;
          height: 16px;
          stroke: currentColor;
        }

        /* Login button - Liquid Glass */
        .login-btn {
          display: inline-flex;
          align-items: center;
          justify-content: center;
          gap: 0.75rem;
          padding: 0.875rem 2rem;
          font-family: 'Outfit', sans-serif;
          font-size: 0.9375rem;
          font-weight: 500;
          color: white;
          text-decoration: none;
          cursor: pointer;
          animation: fade-in 0.8s ease-out 0.45s backwards;

          background: rgba(255, 255, 255, 0.1);
          backdrop-filter: blur(12px);
          -webkit-backdrop-filter: blur(12px);
          mix-blend-mode: difference;

          border: 1px solid rgba(255, 255, 255, 0.4);
          border-radius: 2rem;
          box-shadow: 0 4px 12px rgba(0, 0, 0, 0.2);

          transition: all 0.25s ease;
        }

        .login-btn:hover {
          background: rgba(255, 255, 255, 0.15);
          border-color: rgba(255, 255, 255, 0.5);
          transform: translateY(-2px);
          box-shadow: 0 6px 20px rgba(0, 0, 0, 0.3);
        }

        .login-btn:active {
          transform: translateY(0);
          box-shadow: 0 2px 8px rgba(0, 0, 0, 0.2);
        }

        .login-btn svg {
          width: 18px;
          height: 18px;
        }

        /* Footer */
        .footer {
          margin-top: 3rem;
          animation: fade-in 0.8s ease-out 0.6s backwards;
        }

        .footer a {
          display: inline-flex;
          align-items: center;
          gap: 0.5rem;
          font-size: 0.8125rem;
          color: var(--text-muted);
          text-decoration: none;
          transition: color 0.2s ease;
        }

        .footer a:hover {
          color: var(--text-secondary);
        }

        .footer svg {
          width: 15px;
          height: 15px;
        }

        @keyframes fade-in {
          from {
            opacity: 0;
            transform: translateY(12px);
          }
          to {
            opacity: 1;
            transform: translateY(0);
          }
        }

        /* Responsive */
        @media (max-width: 480px) {
          .brand {
            font-size: 2.5rem;
            margin-bottom: 0.75rem;
          }

          .tagline {
            font-size: 1rem;
            margin-bottom: 2rem;
          }

          .features {
            gap: 1.25rem;
            margin-bottom: 2rem;
          }

          .feature {
            font-size: 0.8125rem;
          }

          .login-btn {
            padding: 0.75rem 1.5rem;
            font-size: 0.875rem;
          }

          .footer {
            margin-top: 2rem;
          }
        }
      </style>
    </head>
    <body>
      <!-- Perspective grid background with orbs -->
      <canvas id="canvas-bottom" class="orb-canvas"></canvas>
      <div class="grid-bg">
        <div class="grid-plane"></div>
      </div>
      <canvas id="canvas-top" class="orb-canvas"></canvas>

      <div class="container">
        <!-- Brand -->
        <h1 class="brand">burrow</h1>

        <!-- Tagline -->
        <p class="tagline">Expose your local services to the internet through secure tunnels</p>

        <!-- Features -->
        <div class="features">
          <div class="feature">
            <svg viewBox="0 0 24 24" fill="none" stroke-width="2">
              <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>
            </svg>
            Secure
          </div>
          <div class="feature">
            <svg viewBox="0 0 24 24" fill="none" stroke-width="2">
              <circle cx="12" cy="12" r="10"/>
              <polyline points="12 6 12 12 16 14"/>
            </svg>
            Fast
          </div>
          <div class="feature">
            <svg viewBox="0 0 24 24" fill="none" stroke-width="2">
              <path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z"/>
            </svg>
            Simple
          </div>
        </div>

        <!-- Login button -->
        <a href="/auth/login" class="login-btn">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <rect x="3" y="11" width="18" height="11" rx="2" ry="2"/>
            <path d="M7 11V7a5 5 0 0 1 10 0v4"/>
          </svg>
          Sign in
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

      <script>
      (function(){
        'use strict';

        var GRID = 40;
        var DEG = Math.PI / 180;
        var PERSPECTIVE = 400;
        var RX = 45 * DEG;
        var cosX = Math.cos(RX), sinX = Math.sin(RX);

        var opts = {
          numberOrbs: 250,
          maxVelocity: 0.8,
          orbRadius: 2.5,
          minProximity: 50,
          maxDepthDiff: 150,
          turnChance: 0.25,
          colorFrequency: 0.06,
          colorAngleIncrement: 0.002,
          globalAlpha: 0.008,
          trailFade: 0.035
        };

        var canvasTop, linecxt, canvasBottom, cxt, viewW, viewH, planeW, planeH, originX, originY, animationFrame;
        var orbs, colorAngle = 0;

        function project(gx, gy) {
          var rx = gx - planeW / 2;
          var ry = planeH - gy;
          var y2 = ry * cosX;
          var z2 = ry * sinX;
          var scale = PERSPECTIVE / (PERSPECTIVE + z2);
          return { x: rx * scale + originX, y: viewH - y2 * scale, scale: scale };
        }

        function snapToGrid(val) {
          return Math.round(val / GRID) * GRID;
        }

        function Orb(radius) {
          var gridCols = Math.floor(planeW / GRID);
          var gridRows = Math.floor(planeH / GRID);
          this.gx = (Math.floor(Math.random() * gridCols) + 1) * GRID;
          this.gy = (Math.floor(Math.random() * gridRows) + 1) * GRID;
          this.radius = radius;
          this.color = null;
          this.speed = 0.3 + Math.random() * opts.maxVelocity;
          this.horizontal = Math.random() < 0.5;
          this.direction = Math.random() < 0.5 ? 1 : -1;
          this.lastIntersection = null;
          this.projected = { x: 0, y: 0, scale: 1 };
        }

        Orb.prototype.update = function() {
          if (this.horizontal) {
            this.gx += this.speed * this.direction;
            if (this.gx <= 0 || this.gx >= planeW) this.direction *= -1;
          } else {
            this.gy += this.speed * this.direction;
            if (this.gy <= 0 || this.gy >= planeH) this.direction *= -1;
          }

          var onGridX = Math.abs(this.gx - snapToGrid(this.gx)) < this.speed + 0.5;
          var onGridY = Math.abs(this.gy - snapToGrid(this.gy)) < this.speed + 0.5;

          if (onGridX && onGridY) {
            var ix = snapToGrid(this.gx);
            var iy = snapToGrid(this.gy);
            var intersectionKey = ix + ',' + iy;

            if (this.lastIntersection !== intersectionKey && Math.random() < opts.turnChance) {
              this.gx = ix;
              this.gy = iy;
              this.horizontal = !this.horizontal;
              this.lastIntersection = intersectionKey;
            }
          }

          this.projected = project(this.gx, this.gy);
        };

        Orb.prototype.display = function() {
          var p = this.projected;
          if (p.scale <= 0) return;
          cxt.beginPath();
          cxt.fillStyle = this.color;
          cxt.arc(p.x, p.y, this.radius * p.scale, 0, 2 * Math.PI);
          cxt.fill();
        };

        function phaseColor() {
          var r = 140 + Math.floor(Math.sin(opts.colorFrequency * colorAngle) * 20);
          var g = 70 + Math.floor(Math.sin(opts.colorFrequency * colorAngle) * 15);
          var b = 70 + Math.floor(Math.sin(opts.colorFrequency * colorAngle) * 15);
          colorAngle += opts.colorAngleIncrement;
          return 'rgba(' + r + ', ' + g + ', ' + b + ', 1)';
        }

        function initialize() {
          canvasTop = document.querySelector('#canvas-top');
          canvasBottom = document.querySelector('#canvas-bottom');
          if (!canvasTop || !canvasBottom) return;
          linecxt = canvasTop.getContext('2d');
          cxt = canvasBottom.getContext('2d');
          window.addEventListener('resize', resize, false);
          resize();
        }

        function resize() {
          viewW = window.innerWidth;
          viewH = window.innerHeight;
          planeW = viewW * 4;
          planeH = viewH * 2.5;
          originX = viewW * 0.5;
          originY = viewH;
          setup();
        }

        function setup() {
          canvasTop.width = viewW;
          canvasTop.height = viewH;
          canvasBottom.width = viewW;
          canvasBottom.height = viewH;
          orbs = [];
          for (var i = 0; i < opts.numberOrbs; i++) {
            orbs.push(new Orb(opts.orbRadius));
          }
          if (animationFrame !== undefined) cancelAnimationFrame(animationFrame);
          draw();
        }

        function draw() {
          cxt.clearRect(0, 0, viewW, viewH);

          // Fade trail canvas gradually
          linecxt.globalCompositeOperation = 'destination-out';
          linecxt.fillStyle = 'rgba(0, 0, 0, ' + opts.trailFade + ')';
          linecxt.fillRect(0, 0, viewW, viewH);
          linecxt.globalCompositeOperation = 'source-over';

          var color = phaseColor();

          for (var i = 0; i < orbs.length; i++) {
            orbs[i].color = color;
            orbs[i].update();
            orbs[i].display();

            for (var j = i + 1; j < orbs.length; j++) {
              var oi = orbs[i], oj = orbs[j];
              var depthDiff = Math.abs(oi.gy - oj.gy);
              if (depthDiff > opts.maxDepthDiff) continue;

              var pi = oi.projected, pj = oj.projected;
              var dx = pi.x - pj.x, dy = pi.y - pj.y;
              var d = Math.sqrt(dx * dx + dy * dy);
              if (d <= opts.minProximity) {
                linecxt.beginPath();
                linecxt.strokeStyle = color;
                linecxt.globalAlpha = opts.globalAlpha;
                linecxt.moveTo(pi.x, pi.y);
                linecxt.lineTo(pj.x, pj.y);
                linecxt.stroke();
              }
            }
          }
          animationFrame = requestAnimationFrame(draw);
        }

        initialize();
      })();
      </script>
    </body>
    </html>
    """
  end
end
