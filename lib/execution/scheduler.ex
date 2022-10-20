defmodule Journey.Execution.Scheduler2 do
  import Journey.Utilities, only: [f_name: 0]
  require Logger

  def advance(execution_id) when is_binary(execution_id) do
    execution_id
    |> Journey.Execution.Store.load(false)
    |> advance()
  end

  def advance(execution) when is_map(execution) do
    # Schedule all the tasks that need to be scheduled.

    execution =
      execution
      |> Journey.Execution.Store.load()

    # |> IO.inspect(label: "reloaded execution1")

    execution
    |> get_schedulable_steps()
    # |> IO.inspect(label: "schedulable computations for chickens")
    |> Enum.map(fn process_step -> try_scheduling_process_tasks(process_step, execution) end)

    execution =
      execution
      |> Journey.Execution.Store.load()

    execution
    |> get_runnable_process_steps()
    |> case do
      [] ->
        execution

      [runnable_process_step | _] ->
        execution
        |> try_running(runnable_process_step)
        |> advance()
    end
  end

  defp get_schedulable_steps(execution) do
    func_name = "#{f_name()}[#{execution.id}]"
    Logger.info("#{func_name}: enter")
    # IO.inspect(execution, label: "execution in get_schedulable_steps")
    process = Journey.ProcessCatalog.get(execution.process_id)

    process.steps
    # We only care about tasks that can be scheduled.
    |> Enum.filter(fn process_step -> process_step.func_next_execution_time_epoch_seconds != nil end)
    # We only care about tasks that are not already scheduled.
    |> Enum.filter(fn process_step ->
      execution
      |> Journey.Execution.Queries.get_sorted_computations_by_status(process_step.name, :scheduled)
      |> Enum.empty?()
      |> dbg()
    end)
    # |> IO.inspect(label: "yes or no")
    # We only care about steps that don't have any unfulfilled upstream dependencies.
    |> Enum.filter(fn process_step -> !has_outstanding_dependencies?(process_step, execution) end)

    # |> IO.inspect(label: "why oh why")
    # |> dbg()

    # |> Enum.map(fn process_step -> process_step.name end)
  end

  defp try_scheduling_process_tasks(process_step, execution) do
    # def async_computation_processing(execution, process_step) do
    func_name = "#{f_name()}[#{execution.id}.#{process_step.name}]"
    Logger.debug("#{func_name}: starting")

    now = Journey.Utilities.curent_unix_time_sec()

    # TODO: handle scheduled computations that missed their scheduled time by a lot.
    scheduled_computations =
      execution
      |> Journey.Execution.Queries.get_sorted_computations(process_step.name)
      |> Enum.filter(fn computation -> computation.result_code == :scheduled end)
      |> Enum.take(1)

    if Enum.empty?(scheduled_computations) do
      # The task is not currently scheduled to be computed. Attempt to schedule it.
      try_scheduling_a_scheduled_step(execution, process_step)
    else
      Logger.error("#{func_name}: computation already scheduled, #{inspect(scheduled_computations, pretty: true)}")
    end

    Logger.debug("#{func_name}: exit")

    # TODO: can we return an updated execution here?
    execution
  end

  defp get_runnable_process_steps(execution) do
    []
  end

  defp try_running(execution, runnable_process_step) do
    execution
  end

  defp has_outstanding_dependencies?(step, execution) do
    log_prefix = "#{f_name()}[#{execution.id}.#{step.name}]"

    Logger.debug("#{log_prefix}: step in question: #{inspect(step, pretty: true)}")

    computed_step_names =
      execution.computations
      |> Enum.filter(fn c ->
        c.result_code == :computed
      end)
      |> Enum.map(fn c -> c.name end)
      |> MapSet.new()

    all_upstream_steps_names =
      step.blocked_by |> Enum.map(fn upstream_step -> upstream_step.step_name end) |> MapSet.new()

    remaining_upstream_steps = MapSet.difference(all_upstream_steps_names, computed_step_names) |> MapSet.to_list()

    case remaining_upstream_steps do
      [] ->
        Logger.info("#{log_prefix}: not blocked, ready to compute or to be scheduled.")
        false

      _ ->
        Logger.info("#{log_prefix}: blocked by upstream steps: #{Enum.join(remaining_upstream_steps, ", ")}")
        true
    end
  end

  defp try_scheduling_a_scheduled_step(execution, process_step) do
    func_name = "#{f_name()}[#{execution.id}.#{process_step.name}]"
    Logger.info("#{func_name}: starting")

    Journey.Execution.Store.create_new_scheduled_computation_record_maybe(
      execution,
      process_step.name,
      process_step.func_next_execution_time_epoch_seconds.(execution)
    )
    |> case do
      {:ok, scheduled_computation_object} ->
        # Successfully created a scheduled computation object.
        Logger.info("#{func_name}: created a new scheduled computation object, id: #{scheduled_computation_object.id}")

      {:error, :computation_already_scheduled} ->
        # The computation object for this step already exists. No need to perform the computation.
        Logger.warn("#{func_name}: a computation for this task is already scheduled, not scheduling another.")
    end

    execution
  end
end
