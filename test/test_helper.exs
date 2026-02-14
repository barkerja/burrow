ExUnit.start()

if Burrow.Repo.enabled?() do
  Ecto.Adapters.SQL.Sandbox.mode(Burrow.Repo, :manual)
end
