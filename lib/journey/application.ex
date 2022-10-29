defmodule Journey.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def sweeper_period_seconds() do
    case Application.get_env(:journey, :sweeper_period_seconds) do
      nil ->
        5

      configured_value ->
        configured_value
    end
  end

  def start(_type, _args) do
    children = [
      # Starts a worker by calling: MyApp.Worker.start_link(arg)
      # {MyApp.Worker, arg}
      {Journey.Repo, []},
      Journey.ProcessCatalog,
      {Task,
       fn ->
         Journey.Execution.Daemons.delay_and_sweep_task(sweeper_period_seconds())
       end}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Journey.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
