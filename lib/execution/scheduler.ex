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

    execution
    |> get_schedulable_steps()
    |> Enum.each(fn process_step -> try_scheduling_process_tasks(process_step, execution) end)

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
    # We only care about steps that don't have any unfulfilled upstream dependencies.
    |> Enum.filter(fn process_step -> !has_outstanding_dependencies?(process_step, execution) end)

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
    # TODO: move scheduling logic to, perhaps, a dedicated module.
    process = Journey.ProcessCatalog.get(execution.process_id)

    all_runnable_steps =
      process.steps
      |> Enum.filter(fn c -> c.func != nil end)
      |> Enum.map(fn p -> p.name end)
      |> MapSet.new()

    now = Journey.Utilities.curent_unix_time_sec()

    one_time_computations =
      execution.computations
      |> Enum.filter(fn c -> c.scheduled_time == 0 end)
      |> Enum.filter(fn c -> c.result_code in [:computing, :computed, :failed] end)
      |> Enum.map(fn c -> c.name end)
      |> MapSet.new()

    all_schedulable_taks =
      process.steps
      |> Enum.filter(fn process_step -> process_step.func_next_execution_time_epoch_seconds == 0 end)
      |> Enum.map(fn c -> c.name end)
      |> MapSet.new()

    all_scheduled_computations_whose_time_has_come =
      execution.computations
      |> Enum.filter(fn c -> c.scheduled_time <= now end)
      |> Enum.filter(fn c -> c.result_code == :scheduled end)
      |> Enum.map(fn c -> c.name end)
      |> MapSet.new()

    # all_step_names - one_time_computations - all_schedulable_taks + all_scheduled_computations_whose_time_has_come

    all_runnable_steps
    # Subtract all one-time computations that have taken place / are taking place.
    |> MapSet.difference(one_time_computations)
    # Subtract all schedulable tasks.
    |> MapSet.difference(all_schedulable_taks)
    # Add back all scheduled tasks whose time has come.
    |> MapSet.union(all_scheduled_computations_whose_time_has_come)
    # credo:disable-for-next-line Credo.Check.Refactor.FilterFilter
    |> Enum.filter(fn step_name ->
      step = Journey.Process.find_step_by_name(process, step_name)
      !has_outstanding_dependencies?(step, execution)
    end)
    |> IO.inspect(label: "duck: steps not computed and not blocked")
  end

  defp try_running(execution, runnable_process_step) do
    IO.inspect(runnable_process_step, label: "goose try to execute these tasks")
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

  # defp try_computing_a_scheduled_task(execution, process_step) do
  #   func_name = "#{f_name()}[#{execution.id}.#{process_step.name}]"
  #   Logger.info("#{func_name}: starting")

  #   Journey.Execution.Store.mark_scheduled_computation_as_computing(
  #     execution,
  #     process_step.name,
  #     process_step.expires_after_seconds
  #   )
  #   |> case do
  #     {:ok, computation_object} ->
  #       # TODO: move the calls to `process_step.func.(execution)` and its handling to a separate function.
  #       # Successfully updated a scheduled computation object. Proceed with the computation.
  #       try do
  #         Logger.info("#{func_name}: picked up a scheduled computation object, starting the computation")
  #         # TODO: handle {:error, ...}
  #         {:ok, result} = process_step.func.(execution)

  #         Journey.Execution.Store.complete_computation_and_record_result(
  #           execution,
  #           computation_object,
  #           process_step.name,
  #           result
  #         )
  #       rescue
  #         exception ->
  #           # Processing failed.
  #           error_string = Exception.format(:error, exception, __STACKTRACE__)

  #           Logger.error(
  #             "#{func_name}: failed to execute this step's function. computation id: #{computation_object.id}, error: #{error_string}"
  #           )

  #           Journey.Execution.Store.mark_computation_as_failed(
  #             execution,
  #             computation_object,
  #             process_step.name,
  #             error_string
  #           )
  #       end

  #       # TODO: There is a slight window here, where if the service dies while we are here, another computation will not get scheduled.
  #       # this might lead to the execution getting dropped and never getting processed again (no daemon will pick it up).
  #       #
  #       # a possible direction for a fix is to have a daemon look into executions whose last change
  #       # select computations.name, computations.result_code, executions.revision, executions.id, computations.id from executions join computations on executions.id=computations.execution_id where computations.ex_revision=executions.revision and computations.scheduled_time!=0 and computations.result_code!='scheduled';
  #       kick_off_or_schedule_unblocked_steps_if_any(execution)

  #     {:error, :no_scheduled_computation_exists} ->
  #       # The computation object for this step already exists. No need to perform the computation.
  #       Logger.warn("#{func_name}: computation already exists, not starting")
  #       execution
  #   end
  # end
end
