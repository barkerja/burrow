defmodule Burrow.Repo do
  @moduledoc """
  Ecto Repo for PostgreSQL persistence.
  """

  use Ecto.Repo,
    otp_app: :burrow,
    adapter: Ecto.Adapters.Postgres
end
