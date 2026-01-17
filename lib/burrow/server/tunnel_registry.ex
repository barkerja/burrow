defmodule Burrow.Server.TunnelRegistry do
  @moduledoc """
  Distributed registry mapping subdomains to tunnel connections.

  Uses OTP's `:pg` (process groups) for cluster-wide tunnel discovery.
  Each node maintains local state, but lookups work across the cluster.

  Provides:
  - Registration and lookup of tunnels by subdomain (cluster-wide)
  - Tracking tunnels by client public key (local node only)
  - Automatic cleanup when connection processes die
  """

  use GenServer

  require Logger

  @pg_scope :burrow_tunnels

  @type tunnel_info :: %{
          tunnel_id: String.t(),
          subdomain: String.t(),
          client_public_key: binary(),
          connection_pid: pid(),
          stream_ref: reference(),
          local_host: String.t(),
          local_port: pos_integer(),
          registered_at: DateTime.t()
        }

  @type state :: %{
          tunnels: %{String.t() => tunnel_info()},
          by_public_key: %{binary() => MapSet.t(String.t())}
        }

  # Client API

  @doc """
  Starts the tunnel registry.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Registers a new tunnel.

  Registers both locally and in the distributed process group.

  ## Parameters

  - `:tunnel_id` - Unique identifier for the tunnel
  - `:subdomain` - Requested subdomain
  - `:client_public_key` - Client's Ed25519 public key
  - `:connection_pid` - PID of the connection process
  - `:stream_ref` - Reference to the HTTP/2 stream
  - `:local_host` - Client's local target host
  - `:local_port` - Client's local target port

  ## Returns

  - `{:ok, subdomain}` - On successful registration
  - `{:error, :subdomain_taken}` - If subdomain is already in use (on any node)
  """
  @spec register(map()) :: {:ok, String.t()} | {:error, :subdomain_taken}
  def register(params) do
    GenServer.call(__MODULE__, {:register, params})
  end

  @doc """
  Unregisters a tunnel by subdomain.
  """
  @spec unregister(String.t()) :: :ok
  def unregister(subdomain) do
    GenServer.cast(__MODULE__, {:unregister, subdomain})
  end

  @doc """
  Looks up a tunnel by subdomain across the cluster.

  First checks the distributed process group to find which node
  has the tunnel, then retrieves the full tunnel info.

  ## Returns

  - `{:ok, tunnel_info}` - If tunnel exists (on any node)
  - `{:error, :not_found}` - If no tunnel registered for subdomain
  """
  @spec lookup(String.t()) :: {:ok, tunnel_info()} | {:error, :not_found}
  def lookup(subdomain) do
    # First check distributed process group for the tunnel
    case :pg.get_members(@pg_scope, {:tunnel, subdomain}) do
      [] ->
        {:error, :not_found}

      [connection_pid | _] ->
        # Found it! Get tunnel info from the node that owns it
        get_tunnel_info(connection_pid, subdomain)
    end
  end

  @doc """
  Returns all tunnels registered by a specific client public key.
  Note: This only returns tunnels on the local node.
  """
  @spec list_by_client(binary()) :: [tunnel_info()]
  def list_by_client(public_key) do
    GenServer.call(__MODULE__, {:list_by_client, public_key})
  end

  @doc """
  Returns the number of currently registered tunnels on this node.
  """
  @spec count() :: non_neg_integer()
  def count do
    GenServer.call(__MODULE__, :count)
  end

  @doc """
  Returns the total number of tunnels across the cluster.
  """
  @spec cluster_count() :: non_neg_integer()
  def cluster_count do
    :pg.which_groups(@pg_scope)
    |> Enum.count(fn
      {:tunnel, _subdomain} -> true
      _ -> false
    end)
  end

  @doc """
  Returns tunnel info for a tunnel owned by this process.
  Called remotely by other nodes during distributed lookup.
  """
  @spec get_local_tunnel_info(String.t()) :: {:ok, tunnel_info()} | {:error, :not_found}
  def get_local_tunnel_info(subdomain) do
    GenServer.call(__MODULE__, {:lookup_local, subdomain})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Start the pg scope if not already started
    case :pg.start_link(@pg_scope) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    {:ok, %{tunnels: %{}, by_public_key: %{}}}
  end

  @impl true
  def handle_call({:register, params}, _from, state) do
    subdomain = params.subdomain

    # Check if subdomain is taken anywhere in the cluster
    case :pg.get_members(@pg_scope, {:tunnel, subdomain}) do
      [_ | _] ->
        {:reply, {:error, :subdomain_taken}, state}

      [] ->
        # Also check local state (race condition protection)
        if Map.has_key?(state.tunnels, subdomain) do
          {:reply, {:error, :subdomain_taken}, state}
        else
          tunnel_info = build_tunnel_info(params)

          # Join the distributed process group
          :ok = :pg.join(@pg_scope, {:tunnel, subdomain}, params.connection_pid)

          # Monitor the connection process for cleanup
          Process.monitor(params.connection_pid)

          tunnels = Map.put(state.tunnels, subdomain, tunnel_info)

          # Use MapSet for O(1) operations and deduplication
          by_pk =
            Map.update(
              state.by_public_key,
              params.client_public_key,
              MapSet.new([subdomain]),
              &MapSet.put(&1, subdomain)
            )

          Logger.info("[TunnelRegistry] Registered tunnel #{subdomain} on #{node()}")
          {:reply, {:ok, subdomain}, %{state | tunnels: tunnels, by_public_key: by_pk}}
        end
    end
  end

  @impl true
  def handle_call({:lookup_local, subdomain}, _from, state) do
    case Map.fetch(state.tunnels, subdomain) do
      {:ok, info} -> {:reply, {:ok, info}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:list_by_client, public_key}, _from, state) do
    subdomains = Map.get(state.by_public_key, public_key, MapSet.new())

    tunnels =
      subdomains
      |> MapSet.to_list()
      |> Enum.map(&Map.get(state.tunnels, &1))
      |> Enum.reject(&is_nil/1)

    {:reply, tunnels, state}
  end

  @impl true
  def handle_call(:count, _from, state) do
    {:reply, map_size(state.tunnels), state}
  end

  @impl true
  def handle_cast({:unregister, subdomain}, state) do
    {:noreply, remove_tunnel(state, subdomain)}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Remove all tunnels for this connection
    tunnels_to_remove =
      state.tunnels
      |> Enum.filter(fn {_subdomain, info} -> info.connection_pid == pid end)
      |> Enum.map(fn {subdomain, _} -> subdomain end)

    state = Enum.reduce(tunnels_to_remove, state, &remove_tunnel(&2, &1))
    {:noreply, state}
  end

  # Private functions

  defp build_tunnel_info(params) do
    %{
      tunnel_id: params.tunnel_id,
      subdomain: params.subdomain,
      client_public_key: params.client_public_key,
      connection_pid: params.connection_pid,
      stream_ref: params.stream_ref,
      local_host: params.local_host,
      local_port: params.local_port,
      registered_at: DateTime.utc_now()
    }
  end

  defp remove_tunnel(state, subdomain) do
    case Map.pop(state.tunnels, subdomain) do
      {nil, _} ->
        state

      {info, tunnels} ->
        # Leave the distributed process group
        :pg.leave(@pg_scope, {:tunnel, subdomain}, info.connection_pid)

        Logger.info("[TunnelRegistry] Unregistered tunnel #{subdomain} from #{node()}")

        # Update MapSet and clean up empty sets to prevent memory leak
        by_pk =
          case Map.get(state.by_public_key, info.client_public_key) do
            nil ->
              state.by_public_key

            set ->
              new_set = MapSet.delete(set, subdomain)

              if MapSet.size(new_set) == 0 do
                # Remove the key entirely when empty to free memory
                Map.delete(state.by_public_key, info.client_public_key)
              else
                Map.put(state.by_public_key, info.client_public_key, new_set)
              end
          end

        %{state | tunnels: tunnels, by_public_key: by_pk}
    end
  end

  defp get_tunnel_info(connection_pid, subdomain) do
    # The connection_pid encodes which node it's on
    # If it's on this node, call locally; otherwise make a remote call
    if node(connection_pid) == node() do
      get_local_tunnel_info(subdomain)
    else
      # Call the registry on the remote node
      try do
        GenServer.call({__MODULE__, node(connection_pid)}, {:lookup_local, subdomain}, 5000)
      catch
        :exit, _ -> {:error, :not_found}
      end
    end
  end
end
