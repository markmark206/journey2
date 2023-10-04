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

  def register_itinerary(itinerary) do
    Logger.info("register_itinerary: '#{itinerary.process_id}'")

    itinerary
    |> prepend_with_start_time()
    |> Journey.ProcessCatalog.register()
    |> tap(fn it -> update_all_executions_with_tasks(itinerary.process_id) end)
  end

  def start(itinerary) do
    register_itinerary(itinerary)

    _execution =
      itinerary.process_id
      |> Journey.Execution.new()
      |> Journey.Execution.set_value(:started_at, Journey.Utilities.curent_unix_time_sec())
  end

  def update_all_executions_with_tasks(process_id) do
    # TODO: introduce the notion of process version, and only update the executions from older process ids.
    # TODO: add a test.
    Logger.info("update_all_executions_with_tasks: for process '#{process_id}'")

    for execution <- Journey.Execution.Store.get_all_executions_for_process(process_id) do
      Logger.info("evaluating execution #{execution.id}")
      Journey.Execution.Scheduler2.advance(execution)
    end
  end

  def find_step_by_name(process, step_name) when is_atom(step_name) do
    process.steps
    |> Enum.find(fn s -> s.name == step_name end)
  end

  #  @two_minutes_in_seconds 2 * 60
  #
  # # TODO: remove these from this module, and use Daemon's tasks directly.
  # @spec kick_off_background_tasks(number) :: {:ok, pid()}
  # def kick_off_background_tasks(min_delay_seconds \\ @two_minutes_in_seconds) do
  #   Logger.info("#{f_name()}: kicking off background tasks. base delay: #{min_delay_seconds} seconds")

  #   {:ok, _pid} =
  #     Journey.Execution.Daemons.start(min_delay_seconds)
  #     |> tap(fn _ -> Logger.info("#{f_name()}: background tasks started") end)
  # end

  # def shutdown_background_tasks(pid) do
  #   Journey.Execution.Daemons.shutdown(pid)
  # end
end
