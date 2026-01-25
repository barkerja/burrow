defmodule Burrow.Workers.IPLookupWorker do
  @moduledoc """
  Oban worker for asynchronous IP geolocation lookups.

  Looks up IP information and updates the request record with the result.
  Retries automatically on failure with exponential backoff.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [period: 60, keys: [:request_id]]

  alias Burrow.Server.{IPLookup, RequestStore}

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"request_id" => request_id, "client_ip" => client_ip, "type" => type}
      }) do
    case IPLookup.lookup_sync(client_ip) do
      {:ok, ip_info} ->
        case type do
          "request" ->
            RequestStore.update_ip_info(request_id, ip_info)

          "unknown_request" ->
            RequestStore.update_unknown_request_ip_info(request_id, ip_info)
        end

        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end
end
