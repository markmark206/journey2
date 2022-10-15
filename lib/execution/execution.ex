defmodule Journey.Execution do
  require Logger
  # defstruct [
  #  :id,
  #  :process_id,
  #  :computations
  # ]

  def new(process_id) do
    Journey.Execution.Store.create_initial_record(process_id)
  end

  def get_computation(execution, computation_name) do
    # TODO: replace this biz with a dictionary lookup.
    # TODO: detect and handle multiple computations of the same name.
    execution.computations
    |> Enum.find(fn c -> c.name == computation_name end)
  end

  def get_computation_status(execution, computation_name) do
    execution
    |> get_computation(computation_name)
    |> case do
      nil -> nil
      computation -> computation.result_code
    end
  end

  def set_value(execution, step, value) do
    execution = Journey.Execution.Store.set_value(execution, step, value)
    kick_off_unblocked_steps(execution)
    # TODO: have kick_off_unblocked_steps return an updated execution, and return that execution instead.
    execution
  end

  def reload(execution) do
    execution |> Journey.Execution.Store.load()
  end

  def get_unfilled_steps(_execution) do
    []
  end

  def get_summary(execution) do
    "execution summary. TODO: implement '#{execution.id}'"
  end

  defp has_outstanding_dependencies?(step, execution, computed_step_names) do
    log_prefix = "has_outstanding_dependencies?[#{execution.id}]"

    Logger.info("#{log_prefix}: task '#{step.name}' step in question: #{inspect(step, pretty: true)}")

    all_upstream_steps_names =
      step.blocked_by |> Enum.map(fn upstream_step -> upstream_step.step_name end) |> MapSet.new()

    remaining_upstream_steps = MapSet.difference(all_upstream_steps_names, computed_step_names) |> MapSet.to_list()

    case remaining_upstream_steps do
      [] ->
        Logger.info("#{log_prefix}: task '#{step.name}'. not waiting for anything, ready to compute")

        false

      _ ->
        Logger.info("#{log_prefix}: task '#{step.name}'. waiting for #{} upstream steps ()")

        true
    end
  end

  defp find_steps_not_yet_computed(execution, process) do
    all_step_names = process.steps |> Enum.map(fn p -> p.name end) |> MapSet.new()
    all_computed_step_names = execution.computations |> Enum.map(fn c -> c.name end) |> MapSet.new()

    steps_not_yet_computed_names =
      MapSet.difference(
        all_step_names,
        all_computed_step_names
      )

    process_steps_not_yet_computed =
      process.steps
      |> Enum.filter(fn step ->
        MapSet.member?(steps_not_yet_computed_names, step.name)
      end)

    Logger.info(
      "kick_off_unblocked_steps[#{execution.id}]: #{Enum.count(steps_not_yet_computed_names)} steps available for execution: '#{Enum.join(steps_not_yet_computed_names, ", ")}"
    )

    process_steps_not_yet_computed
    |> Enum.filter(fn step -> step.func != nil end)
    |> Enum.filter(fn step ->
      !has_outstanding_dependencies?(step, execution, all_computed_step_names)
    end)
  end

  defp start_computing(step, execution) do
    set_value(execution, step.name, "let's call this done")
  end

  defp kick_off_unblocked_steps(execution) do
    process = Journey.ProcessCatalog.get(execution.process_id)

    execution
    |> find_steps_not_yet_computed(process)
    |> case do
      [] ->
        Logger.info("kick_off_unblocked_steps[#{execution.id}]: no steps available to be computed")
        {:ok, execution}

      [step | _] ->
        Logger.info("kick_off_unblocked_steps[#{execution.id}]: step '#{step.name}' is ready to be computed")
        execution = start_computing(step, execution)
        kick_off_unblocked_steps(execution)
        # {:ok, execution}

        # computing_value = %Journey.Value{
        #   name: step.name,
        #   value: "computing",
        #   update_time: System.os_time(:second),
        #   status: :computing
        # }

        # execution =
        #   case Journey.ExecutionStore.Postgres.update_value(
        #          execution.execution_id,
        #          step.name,
        #          :not_computed,
        #          computing_value
        #        ) do
        #     {:ok, execution} ->
        #       {:ok, execution} = kickoff(execution, step)
        #       execution

        #     {:not_updated_due_to_current_status, execution} ->
        #       # It looks like the step has already been picked up by someone else, never mind.
        #       execution
        #   end

        # # kick off other steps, if any.
        # kick_off_unblocked_steps(execution)
    end
  end
end
