defmodule Burrow.Server.IPLookup do
  @moduledoc """
  Asynchronous IP geolocation and hostname lookup service.

  Uses ip-api.com for geolocation (free, no API key required).
  Caches results to avoid repeated lookups for the same IP.
  """

  use GenServer

  require Logger

  @cache_table :burrow_ip_cache
  @cache_ttl_ms :timer.hours(24)
  @lookup_timeout_ms 5_000

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Looks up IP information asynchronously.
  Returns cached result immediately if available, otherwise triggers async lookup.

  Returns:
  - `{:ok, info}` - Cached info available
  - `{:pending, ref}` - Lookup in progress, will send `{:ip_lookup, ref, info}` when done
  - `{:error, reason}` - Lookup failed
  """
  def lookup(ip) when is_binary(ip) do
    case get_cached(ip) do
      {:ok, info} ->
        {:ok, info}

      :not_found ->
        GenServer.cast(__MODULE__, {:lookup, ip, self()})
        {:pending, ip}
    end
  end

  @doc """
  Synchronous lookup - waits for result.
  """
  def lookup_sync(ip, timeout \\ @lookup_timeout_ms) when is_binary(ip) do
    case get_cached(ip) do
      {:ok, info} ->
        {:ok, info}

      :not_found ->
        GenServer.call(__MODULE__, {:lookup_sync, ip}, timeout)
    end
  end

  @doc """
  Gets cached IP info if available.
  """
  def get_cached(ip) do
    case :ets.lookup(@cache_table, ip) do
      [{^ip, info, expires_at}] ->
        if System.monotonic_time(:millisecond) < expires_at do
          {:ok, info}
        else
          :ets.delete(@cache_table, ip)
          :not_found
        end

      [] ->
        :not_found
    end
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    :ets.new(@cache_table, [:named_table, :set, :public, read_concurrency: true])
    {:ok, %{pending: %{}}}
  end

  @impl true
  def handle_cast({:lookup, ip, caller}, state) do
    # Start async lookup
    Task.start(fn ->
      info = do_lookup(ip)
      cache_result(ip, info)
      send(caller, {:ip_lookup, ip, info})
    end)

    {:noreply, state}
  end

  @impl true
  def handle_call({:lookup_sync, ip}, _from, state) do
    info = do_lookup(ip)
    cache_result(ip, info)
    {:reply, {:ok, info}, state}
  end

  # Private Functions

  defp do_lookup(ip) do
    info = %{
      ip: ip,
      hostname: nil,
      isp: nil,
      org: nil,
      city: nil,
      region: nil,
      country: nil,
      country_code: nil
    }

    info =
      case lookup_geolocation(ip) do
        {:ok, geo} -> Map.merge(info, geo)
        _ -> info
      end

    case lookup_hostname(ip) do
      {:ok, hostname} -> Map.put(info, :hostname, hostname)
      _ -> info
    end
  end

  defp lookup_geolocation(ip) do
    # Skip private/local IPs
    if private_ip?(ip) do
      {:ok, %{isp: "Private Network", city: "Local", region: nil, country: nil}}
    else
      url = ~c"http://ip-api.com/json/#{ip}?fields=status,isp,org,city,regionName,country,countryCode"

      case :httpc.request(:get, {url, []}, [timeout: @lookup_timeout_ms], body_format: :binary) do
        {:ok, {{_, 200, _}, _headers, body}} ->
          case Jason.decode(body) do
            {:ok, %{"status" => "success"} = data} ->
              {:ok,
               %{
                 isp: data["isp"],
                 org: data["org"],
                 city: data["city"],
                 region: data["regionName"],
                 country: data["country"],
                 country_code: data["countryCode"]
               }}

            {:ok, %{"status" => "fail"}} ->
              {:error, :lookup_failed}

            _ ->
              {:error, :parse_error}
          end

        {:error, reason} ->
          Logger.debug("[IPLookup] Geolocation failed for #{ip}: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp lookup_hostname(ip) do
    case :inet.parse_address(String.to_charlist(ip)) do
      {:ok, addr} ->
        case :inet.gethostbyaddr(addr) do
          {:ok, {:hostent, hostname, _, _, _, _}} ->
            {:ok, List.to_string(hostname)}

          _ ->
            {:error, :no_hostname}
        end

      _ ->
        {:error, :invalid_ip}
    end
  end

  defp cache_result(ip, info) do
    expires_at = System.monotonic_time(:millisecond) + @cache_ttl_ms
    :ets.insert(@cache_table, {ip, info, expires_at})
  end

  defp private_ip?(ip) do
    case String.split(ip, ".") do
      ["10" | _] -> true
      ["127" | _] -> true
      ["192", "168" | _] -> true
      ["172", second | _] ->
        case Integer.parse(second) do
          {n, ""} when n >= 16 and n <= 31 -> true
          _ -> false
        end
      _ -> false
    end
  end
end
