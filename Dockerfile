# Build stage
FROM hexpm/elixir:1.18.0-erlang-27.2-alpine-3.21.0 AS builder

# Install build dependencies
RUN apk add --no-cache git build-base

# Set build environment
ENV MIX_ENV=prod

WORKDIR /app

# Install hex and rebar
RUN mix local.hex --force && mix local.rebar --force

# Copy dependency files
COPY mix.exs mix.lock ./

# Install dependencies
RUN mix deps.get --only prod
RUN mix deps.compile

# Copy application code
COPY lib lib
COPY config config
COPY priv priv
COPY rel rel

# Compile application
RUN mix compile

# Build release
RUN mix release

# Runtime stage - must match Alpine version from build stage
FROM alpine:3.21 AS runtime

# Install runtime dependencies - must match OpenSSL from build
RUN apk add --no-cache libstdc++ libcrypto3 libssl3 ncurses-libs

WORKDIR /app

# Create non-root user
RUN addgroup -g 1000 burrow && \
    adduser -u 1000 -G burrow -s /bin/sh -D burrow

# Create data directory
RUN mkdir -p /var/lib/burrow/acme && \
    chown -R burrow:burrow /var/lib/burrow

# Copy release from builder
COPY --from=builder /app/_build/prod/rel/burrow ./
RUN chown -R burrow:burrow /app

# Set runtime environment
ENV HOME=/app
ENV MIX_ENV=prod
ENV BURROW_MODE=server
ENV ACME_STORAGE_DIR=/var/lib/burrow/acme

# Switch to non-root user (comment out if binding to ports < 1024)
# USER burrow

# Expose ports (HTTP, HTTPS, and TCP tunnel range)
EXPOSE 443 80 40000-40099

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:${HTTP_PORT:-80}/health || exit 1

# Start the application
CMD ["bin/burrow", "start"]
