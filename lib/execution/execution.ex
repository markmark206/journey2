defmodule Journey.Execution do
  require Logger
  # defstruct [
  #  :id,
  #  :process_id,
  #  :computations
  # ]

  def new(process_id) do
    Journey.Execution.Store.create_new_execution_record(process_id)
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

  def get_computation_value(execution, computation_name) do
    execution
    |> get_computation(computation_name)
    |> case do
      nil -> nil
      computation -> computation.result_value
    end
  end

  def set_value(execution, step, value) do
    execution = Journey.Execution.Store.set_value(execution, step, value)
    kick_off_unblocked_steps(execution)
    # TODO: have kick_off_unblocked_steps return an updated execution, and return that execution instead.
    execution
  end

  def reload(execution) do
    # Reload an execution from the db.
    execution |> Journey.Execution.Store.load()
  end

  def get_summary(execution) do
    "execution summary. TODO: implement '#{execution.id}'"
  end

  defp has_outstanding_dependencies?(step, execution, computed_step_names) do
    log_prefix = "has_outstanding_dependencies?[#{execution.id}.#{step.name}]"

    Logger.debug("#{log_prefix}: step in question: #{inspect(step, pretty: true)}")

    all_upstream_steps_names =
      step.blocked_by |> Enum.map(fn upstream_step -> upstream_step.step_name end) |> MapSet.new()

    remaining_upstream_steps = MapSet.difference(all_upstream_steps_names, computed_step_names) |> MapSet.to_list()

    case remaining_upstream_steps do
      [] ->
        Logger.info("#{log_prefix}: not blocked, ready to compute")

        false

      _ ->
        Logger.info(
          "#{log_prefix}: blocked by #{Enum.count(remaining_upstream_steps)} upstream steps: (#{Enum.join(remaining_upstream_steps, ", ")})"
        )

        true
    end
  end

  def names_of_steps_not_yet_fully_computed(execution) do
    process = Journey.ProcessCatalog.get(execution.process_id)

    all_step_names = process.steps |> Enum.map(fn p -> p.name end) |> MapSet.new()

    all_fully_computed_step_names =
      execution.computations
      |> Enum.filter(fn c -> c.result_code == :computed end)
      |> Enum.map(fn c -> c.name end)
      |> MapSet.new()

    MapSet.difference(
      all_step_names,
      all_fully_computed_step_names
    )
  end

  defp find_steps_not_yet_computed_or_computing(execution, process) do
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
      "kick_off_unblocked_steps[#{execution.id}]: #{Enum.count(steps_not_yet_computed_names)} steps available for execution: #{Enum.join(steps_not_yet_computed_names, ", ")}"
    )

    process_steps_not_yet_computed
    |> Enum.filter(fn step -> step.func != nil end)
    # credo:disable-for-next-line Credo.Check.Refactor.FilterFilter
    |> Enum.filter(fn step ->
      !has_outstanding_dependencies?(step, execution, all_computed_step_names)
    end)
  end

  defp start_computing_if_not_already_being_computed(step, execution) do
    # If this step is not already being computed, start the computation.
    func_name = "start_computing[#{execution.id}.#{step.name}]"
    Logger.debug("#{func_name}: starting")

    Journey.Execution.Store.create_new_computation_record_if_one_doesnt_exist(execution, step.name)
    |> case do
      {:ok, computation_object} ->
        # Successfully created a computation object. Proceed with the computation.
        Logger.info("#{func_name}: created a new computation object, performing the computation")
        # TODO: kick off an asynchronous execution.
        {:ok, result} = step.func.(execution)
        Journey.Execution.Store.complete_computation_and_record_result(execution, computation_object, step.name, result)

      {:error, :computation_exists} ->
        # The computation object for this step already exists. No need to perform the computation.
        Logger.warn("#{func_name}: computation already exists, not starting")
    end

    execution |> reload()
  end

  defp kick_off_unblocked_steps(execution) do
    process = Journey.ProcessCatalog.get(execution.process_id)

    execution
    |> find_steps_not_yet_computed_or_computing(process)
    |> case do
      [] ->
        Logger.info("kick_off_unblocked_steps[#{execution.id}]: no steps available to be computed")
        {:ok, execution}

      [step | _] ->
        Logger.info("kick_off_unblocked_steps[#{execution.id}]: step '#{step.name}' is ready to compute")
        execution = start_computing_if_not_already_being_computed(step, execution)
        kick_off_unblocked_steps(execution)
    end
  end
end
