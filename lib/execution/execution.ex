defmodule Journey.Execution do
  require Logger
  import Journey.Utilities, only: [f_name: 0]

  def new(process_id) do
    Journey.Execution.Store.create_new_execution_record(process_id)
  end

  def set_value(execution, step, value) do
    execution
    |> Journey.Execution.Store.set_value(step, value)
    |> kick_off_or_schedule_unblocked_steps_if_any()
  end

  def reload(execution) do
    # Reload an execution from the db.
    execution |> Journey.Execution.Store.load()
  end

  def get_summary(execution) do
    "execution summary. TODO: implement '#{execution.id}'"
  end

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
    all_step_names = process.steps |> Enum.map(fn p -> p.name end) |> MapSet.new()

    # These steps are not in the "need to be computed" pool.
    all_handled_computations_names =
      execution.computations
      |> Enum.filter(fn c ->
        c.result_code in [:computing, :computed, :scheduled, :failed]
      end)
      |> Enum.map(fn c -> c.name end)
      |> MapSet.new()

    steps_not_yet_computed_names =
      MapSet.difference(
        all_step_names,
        all_handled_computations_names
      )

    process_steps_not_yet_computed =
      process.steps
      |> Enum.filter(fn step ->
        MapSet.member?(steps_not_yet_computed_names, step.name)
      end)

    Logger.info(
      "#{f_name()}[#{execution.id}]: #{Enum.count(steps_not_yet_computed_names)} steps available for execution: #{Enum.join(steps_not_yet_computed_names, ", ")}"
    )

    process_steps_not_yet_computed
    |> Enum.filter(fn step -> step.func != nil end)
    # credo:disable-for-next-line Credo.Check.Refactor.FilterFilter
    |> Enum.filter(fn step ->
      !has_outstanding_dependencies?(step, execution)
    end)
  end

  def sweep_and_revisit_expired_computations() do
    # Sweep expired computations, and kick off processing for corresponding executions.
    Logger.info("#{f_name()}: enter")

    # TODO: what do we want to do with abandoned scheduled tasks? (run them now, or wait until next scheduled time?)
    Journey.Execution.Store.mark_abandoned_computations_as_expired()
    |> Enum.map(fn expired_computation ->
      Logger.info("#{f_name()}: processing expired computation, #{inspect(expired_computation, pretty: true)}")
      expired_computation
    end)
    |> Enum.map(fn expired_computation -> expired_computation.execution_id end)
    |> Enum.uniq()
    # Revisit the execution, those abandoned / expired computations might still need to be computed.
    |> Enum.each(&kick_off_or_schedule_unblocked_steps_if_any/1)

    Logger.info("#{f_name()}: exit")
  end

  defp try_scheduling(execution, process_step) do
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

  defp try_computing_or_scheduling(execution, process_step) do
    # If this step is not already being computed, start the computation.
    # func_name = "#{elem(__ENV__.function, 0)}[#{execution.id}.#{process_step.name}]"
    func_name = "#{f_name()}[#{execution.id}.#{process_step.name}]"
    Logger.debug("#{func_name}: starting")

    {:ok, _pid} =
      Task.start(fn ->
        if process_step.func_next_execution_time_epoch_seconds == nil do
          try_computing(execution, process_step)
        else
          try_scheduling(execution, process_step)
        end
      end)

    Logger.debug("#{func_name}: done")

    execution |> reload()
  end

  defp kick_off_or_schedule_unblocked_steps_if_any(execution_id) when is_binary(execution_id) do
    execution_id
    |> Journey.Execution.Store.load(false)
    |> kick_off_or_schedule_unblocked_steps_if_any()
  end

  defp kick_off_or_schedule_unblocked_steps_if_any(execution) when is_map(execution) do
    log_prefix = "#{f_name()}[#{execution.id}]"
    process = Journey.ProcessCatalog.get(execution.process_id)

    execution =
      execution
      |> reload()

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
