defmodule Burrow.Server.Web.Plugs.RateLimit do
  @moduledoc """
  Simple IP-based rate limiting using ETS.

  Limits requests per IP per time window.
  """

  import Plug.Conn

  @table :rate_limit_buckets

  def init(opts) do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:set, :public, :named_table])
    end

    %{
      limit: Keyword.get(opts, :limit, 10),
      window_ms: Keyword.get(opts, :window_ms, 60_000),
      scope: Keyword.get(opts, :scope, "default")
    }
  end

  def call(conn, %{limit: limit, window_ms: window_ms, scope: scope}) do
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()
    key = {scope, ip}
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, key) do
      [{^key, count, window_start}] when now - window_start < window_ms ->
        if count >= limit do
          conn
          |> put_resp_header("retry-after", to_string(div(window_ms, 1000)))
          |> send_resp(429, "Too many requests")
          |> halt()
        else
          :ets.update_counter(@table, key, {2, 1})
          conn
        end

      _ ->
        :ets.insert(@table, {key, 1, now})
        conn
    end
  end
end
