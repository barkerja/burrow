defmodule Burrow.DataCase do
  @moduledoc """
  Test case template for tests that require database access.

  Only used when DATABASE_URL is configured for testing.
  """

  use ExUnit.CaseTemplate

  alias Burrow.Repo
  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      alias Burrow.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Burrow.DataCase
    end
  end

  setup tags do
    if Repo.enabled?() do
      pid = Sandbox.start_owner!(Repo, shared: not tags[:async])

      on_exit(fn -> Sandbox.stop_owner(pid) end)
    end

    :ok
  end

  @doc """
  Helper to setup sandbox mode when database is enabled.
  """
  def setup_sandbox(tags \\ %{}) do
    if Repo.enabled?() do
      pid = Sandbox.start_owner!(Repo, shared: not tags[:async])
      on_exit(fn -> Sandbox.stop_owner(pid) end)
    end

    :ok
  end
end
