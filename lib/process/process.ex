defmodule Journey.Process do
  require Logger
  import Journey.Utilities, only: [f_name: 0]

  defstruct [
    :process_id,
    :steps
  ]

  @type t :: %__MODULE__{
          process_id: String.t(),
          steps: list()
        }

  defp prepend_with_start_time(itinerary) do
    # Each process includes the "started at" timestamp, holding the execution's start time.
    %{itinerary | steps: [%Journey.Process.Step{name: :started_at}] ++ itinerary.steps}
  end

  def register_itinerary(itinerary) do
    itinerary
    |> prepend_with_start_time()
    |> Journey.ProcessCatalog.register()
  end

  def start(itinerary) do
    register_itinerary(itinerary)

    _execution =
      itinerary.process_id
      |> Journey.Execution.new()
      |> Journey.Execution.set_value(:started_at, Journey.Utilities.curent_unix_time_sec())
  end

  def find_step_by_name(process, step_name) when is_atom(step_name) do
    process.steps
    |> Enum.find(fn s -> s.name == step_name end)
  end

  @two_minutes_in_seconds 2 * 60

  @spec kick_off_background_tasks(number) :: :ok
  def kick_off_background_tasks(min_delay_seconds \\ @two_minutes_in_seconds) do
    Logger.info("#{f_name()}: kicking off background tasks")
    {:ok, _} = Journey.Execution.Daemons.start(min_delay_seconds)
    Logger.info("#{f_name()}: background tasks started")
  end
end
