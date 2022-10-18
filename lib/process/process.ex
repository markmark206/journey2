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

  defp delay_and_sweep(min_delay_in_seconds) do
    # Every once in a while (between min_delay_seconds and 2 * min_delay_seconds),
    # detect and "sweep" abandoned tasks.

    # TODO: move background sweepers into a separate module.

    Logger.info("delay_and_sweep: starting run (base delay: #{min_delay_in_seconds} seconds)")

    to_random_ms = fn base_sec ->
      ((base_sec + base_sec * :rand.uniform()) * 1000) |> round()
    end

    min_delay_in_seconds
    |> then(to_random_ms)
    |> :timer.sleep()

    Journey.Execution.sweep_and_revisit_expired_computations()
    Logger.info("delay_and_sweep: ending run")
    delay_and_sweep(min_delay_in_seconds)
  end

  @two_minutes_in_seconds 2 * 60

  def kick_off_background_tasks(min_delay_seconds \\ @two_minutes_in_seconds) do
    # TODO: kick this off as a supervised task.
    {:ok, _pid} =
      Task.start(fn ->
        delay_and_sweep(min_delay_seconds)
      end)
  end
end
