defmodule Journey.Execution.Scheduler do
  import Journey.Utilities, only: [f_name: 0]
  require Logger

  defp has_outstanding_dependencies?(step, execution) do
    log_prefix = "#{f_name()}[#{execution.id}.#{step.name}]"

    Logger.debug("#{log_prefix}: step in question: #{inspect(step, pretty: true)}")

    # TODO: if this is a schedulable task (it has func_next_execution_time_epoch_seconds), there should not be any
    # outstanding (:scheduled or :computing) computations for this task.
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
        Logger.info("#{log_prefix}: not blocked, ready to compute")

        false

      _ ->
        Logger.info(
          "#{log_prefix}: blocked by upstream steps: (#{Enum.count(remaining_upstream_steps)}) (#{Enum.join(remaining_upstream_steps, ", ")})"
        )

        # process = Journey.ProcessCatalog.get(execution.process_id)

        # remaining_upstream_steps
        # |> Enum.map(fn step_name ->
        #   process.steps
        #   |> Enum.find(fn process_step -> process_step.name == step_name end)
        # end)

        # remaining_upstream_steps
        # |> Enum.map(fn step_name ->
        #   execution.computations
        #   |> Enum.find(fn computation -> computation.name == step_name end)
        # end)

        true
    end
  end

  def names_of_steps_not_yet_fully_computed(execution) do
    process = Journey.ProcessCatalog.get(execution.process_id)

    all_step_names = process.steps |> Enum.map(fn p -> p.name end) |> MapSet.new()

    all_fully_computed_step_names =
      execution.computations
      |> Enum.filter(fn c -> c.result_code in [:computed, :failed] end)
      |> Enum.map(fn c -> c.name end)
      |> MapSet.new()

    MapSet.difference(
      all_step_names,
      all_fully_computed_step_names
    )
  end

  defp find_process_steps_ready_to_be_computed(execution, process) do
    # TODO: move scheduling logic to, perhaps, a dedicated module.
    all_step_names = process.steps |> Enum.map(fn p -> p.name end) |> MapSet.new()

    now = Journey.Utilities.curent_unix_time_sec()
    # Scheduled items whose scheduled time has arrived are fair game.

    # These steps are not in the "need to be computed" pool.
    all_handled_computations_names =
      execution.computations
      |> Enum.filter(fn c ->
        # The computation is in progress, or has completed, or the computation is scheduled, but its time hasn't come yet.
        if c.scheduled_time > 0 do
          # this is a schedulable computation.
          if c.result_code == :scheduled do
            # The task is already scheduled, nothing to do.
            true
          else
            # Is the task schedulable for the future?
            # Note: here is small window here, where this condition will return false negative, but this is fine, it will be addressed on the next examination.
            process_step = Journey.Process.find_step_by_name(process, c.name)
            !(process_step.func_next_execution_time_epoch_seconds.(execution) >= now)
          end
        else
          c.result_code in [:computing, :computed, :failed]
        end
      end)
      |> Enum.map(fn c -> c.name end)
      |> MapSet.new()
      |> IO.inspect(label: "fuck this fascist uprising, handled computations")

    steps_not_yet_computed_names =
      MapSet.difference(
        all_step_names,
        all_handled_computations_names
      )
      |> IO.inspect(label: "chicken steps_not_yet_computed_names")

    process_steps_not_yet_computed =
      process.steps
      |> Enum.filter(fn step ->
        MapSet.member?(steps_not_yet_computed_names, step.name)
      end)

    Logger.info(
      "#{f_name()}[#{execution.id}]: #{Enum.count(steps_not_yet_computed_names)} steps not yet computed: #{Enum.join(steps_not_yet_computed_names, ", ")}"
    )

    process_steps_not_yet_computed
    |> Enum.filter(fn step -> step.func != nil end)
    # credo:disable-for-next-line Credo.Check.Refactor.FilterFilter
    |> Enum.filter(fn step ->
      !has_outstanding_dependencies?(step, execution)
    end)
    |> IO.inspect(label: "duck: steps not computed and not blocked")
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

        kick_off_or_schedule_unblocked_steps_if_any(execution)

      {:error, :computation_already_scheduled} ->
        # The computation object for this step already exists. No need to perform the computation.
        Logger.warn("#{func_name}: scheduled computation already exists, not scheduling another.")

        execution
    end
  end

  defp try_computing_a_scheduled_task(execution, process_step) do
    func_name = "#{f_name()}[#{execution.id}.#{process_step.name}]"
    Logger.info("#{func_name}: starting")

    Journey.Execution.Store.mark_scheduled_computation_as_computing(
      execution,
      process_step.name,
      process_step.expires_after_seconds
    )
    |> case do
      {:ok, computation_object} ->
        # TODO: move the calls to `process_step.func.(execution)` and its handling to a separate function.
        # Successfully updated a scheduled computation object. Proceed with the computation.
        try do
          Logger.info("#{func_name}: picked up a scheduled computation object, starting the computation")
          # TODO: handle {:error, ...}
          {:ok, result} = process_step.func.(execution)

          Journey.Execution.Store.complete_computation_and_record_result(
            execution,
            computation_object,
            process_step.name,
            result
          )
        rescue
          exception ->
            # Processing failed.
            error_string = Exception.format(:error, exception, __STACKTRACE__)

            Logger.error(
              "#{func_name}: failed to execute this step's function. computation id: #{computation_object.id}, error: #{error_string}"
            )

            Journey.Execution.Store.mark_computation_as_failed(
              execution,
              computation_object,
              process_step.name,
              error_string
            )
        end

        # TODO: There is a slight window here, where if the service dies while we are here, another computation will not get scheduled.
        # this might lead to the execution getting dropped and never getting processed again (no daemon will pick it up).
        #
        # a possible direction for a fix is to have a daemon look into executions whose last change
        # select computations.name, computations.result_code, executions.revision, executions.id, computations.id from executions join computations on executions.id=computations.execution_id where computations.ex_revision=executions.revision and computations.scheduled_time!=0 and computations.result_code!='scheduled';
        kick_off_or_schedule_unblocked_steps_if_any(execution)

      {:error, :no_scheduled_computation_exists} ->
        # The computation object for this step already exists. No need to perform the computation.
        Logger.warn("#{func_name}: computation already exists, not starting")
        execution
    end
  end

  defp try_computing(execution, process_step) do
    func_name = "#{f_name()}[#{execution.id}.#{process_step.name}]"
    Logger.info("#{func_name}: starting")

    Journey.Execution.Store.create_new_computation_record_if_one_doesnt_exist_lock(
      execution,
      process_step.name,
      process_step.expires_after_seconds
    )
    |> case do
      {:ok, computation_object} ->
        # Successfully created a computation object. Proceed with the computation.
        try do
          Logger.info("#{func_name}: created a new computation object, performing the computation")
          # TODO: handle {:error, ...}
          {:ok, result} = process_step.func.(execution)

          Journey.Execution.Store.complete_computation_and_record_result(
            execution,
            computation_object,
            process_step.name,
            result
          )
        rescue
          exception ->
            # Processing failed.
            error_string = Exception.format(:error, exception, __STACKTRACE__)

            Logger.error(
              "#{func_name}: failed to execute this step's function. computation id: #{computation_object.id}, error: #{error_string}"
            )

            Journey.Execution.Store.mark_computation_as_failed(
              execution,
              computation_object,
              process_step.name,
              error_string
            )
        end

        kick_off_or_schedule_unblocked_steps_if_any(execution)

      {:error, :computation_exists} ->
        # The computation object for this step already exists. No need to perform the computation.
        Logger.warn("#{func_name}: computation already exists, not starting")
        execution
    end
  end

  def async_computation_processing(execution, process_step) do
    func_name = "#{f_name()}[#{execution.id}.#{process_step.name}]"
    Logger.debug("#{func_name}: starting")

    if process_step.func_next_execution_time_epoch_seconds == nil do
      # This is a regular unblocked step, let's go ahead and try computing it.
      try_computing(execution, process_step)
    else
      # This is a scheduled step.
      now = Journey.Utilities.curent_unix_time_sec()

      # TODO: handle scheduled computations that missed their scheduled time by a lot.
      scheduled_computation =
        execution
        |> Journey.Execution.Queries.get_sorted_computations(process_step.name)
        |> Enum.filter(fn computation -> computation.result_code == :scheduled end)
        |> Enum.take(1)
        |> case do
          [] -> nil
          [c] -> c
        end

      cond do
        scheduled_computation == nil ->
          # The task is not currently scheduled to be computed. Attempt to schedule it.
          try_scheduling_a_scheduled_step(execution, process_step)

        scheduled_computation.scheduled_time <= now ->
          # the task is scheduled, and its time has arrived.
          try_computing_a_scheduled_task(execution, process_step)

        scheduled_computation.scheduled_time > now ->
          # the task is scheduled for the future, nothing to do.
          nil

        true ->
          # Not sure how we actually got here.
          Logger.error(
            "#{func_name}: unexpected scheduled computation, #{inspect(scheduled_computation, pretty: true)}"
          )
      end
    end

    Logger.debug("#{func_name}: exit")
  end

  defp try_computing_or_scheduling(execution, process_step) do
    # If this step is not already being computed, start the computation.
    # func_name = "#{elem(__ENV__.function, 0)}[#{execution.id}.#{process_step.name}]"
    func_name = "#{f_name()}[#{execution.id}.#{process_step.name}]"
    Logger.debug("#{func_name}: starting")

    {:ok, _pid} =
      Task.start(fn ->
        async_computation_processing(execution, process_step)
      end)

    Logger.debug("#{func_name}: done")

    execution |> Journey.Execution.Store.load()
  end

  # TODO: move execution scheduling functionality into its own module.
  def kick_off_or_schedule_unblocked_steps_if_any(execution_id) when is_binary(execution_id) do
    execution_id
    |> Journey.Execution.Store.load(false)
    |> kick_off_or_schedule_unblocked_steps_if_any()
  end

  def kick_off_or_schedule_unblocked_steps_if_any(execution) when is_map(execution) do
    log_prefix = "#{f_name()}[#{execution.id}]"
    process = Journey.ProcessCatalog.get(execution.process_id)

    execution =
      execution
      |> Journey.Execution.Store.load()

    execution
    |> find_process_steps_ready_to_be_computed(process)
    |> case do
      [] ->
        Logger.info("#{log_prefix}: no steps available to be computed")
        execution

      [process_step | _] ->
        Logger.info("#{log_prefix}: step '#{process_step.name}' is ready to compute")

        execution
        |> try_computing_or_scheduling(process_step)
        |> kick_off_or_schedule_unblocked_steps_if_any()
    end
  end
end
