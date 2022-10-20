defmodule Journey.RepoCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      alias Journey.Repo

      import Ecto
      import Ecto.Query
      import Journey.RepoCase

      # and any other stuff
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Journey.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(Journey.Repo, {:shared, self()})
    end

    :ok
  end
end
