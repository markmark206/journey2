defmodule Journey.Process do
  require Logger

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

  def start(itinerary) do
    itinerary =
      itinerary
      |> prepend_with_start_time()
      |> Journey.ProcessCatalog.register()

    _execution =
      itinerary.process_id
      |> Journey.Execution.new()
      |> Journey.Execution.set_value(:started_at, Journey.Utilities.curent_unix_time_sec())
  end

  @two_minutes_in_seconds 2 * 60

  def kick_off_background_tasks(min_delay_seconds \\ @two_minutes_in_seconds) do
    # TODO: kick this off as a supervised task.
    {:ok, _pid} =
      Task.start(fn ->
        Journey.Execution.Daemons.delay_and_sweep(min_delay_seconds)
      end)
  end
end
