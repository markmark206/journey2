defmodule Journey.Execution.Store do
  @moduledoc false

  require Logger
  import Ecto.Query

  @doc """
  Stores an execution.
  """
  def create_new_execution_record(process_id) do
    {:ok, execution_db_record} =
      %Journey.Schema.Execution{
        process_id: process_id
      }
      |> Journey.Repo.insert()

    Logger.debug("create_new_execution_record: created record '#{execution_db_record.id}' for process '#{process_id}'")

    execution_db_record
    |> Journey.Repo.preload([:computations])
  end

  def create_new_computation_record_if_one_doesnt_exist_lock(execution, step_name, expires_after_seconds)
      when is_atom(step_name) do
    # Create a new computation record. If one already exists, tell the caller.

    func_name = "create_new_computation_record_if_one_doesnt_exist_lock[#{execution.id}.#{step_name}]"
    Logger.debug("#{func_name}: starting")

    step_name_string = Atom.to_string(step_name)

    Journey.Repo.transaction(fn repo ->
      execution_db_record =
        from(ex in Journey.Schema.Execution,
          where: ex.id == ^execution.id,
          lock: "FOR UPDATE"
        )
        |> repo.one!()

      from(
        computation in Journey.Schema.Computation,
        where:
          computation.execution_id == ^execution.id and computation.name == ^step_name_string and
            computation.result_code != ^:expired
      )
      |> Journey.Repo.one()
      |> case do
        nil ->
          # Record a ":computing" computation for this.
          # We are doing this inside of "for update", which protects against multiple processes inserting this record.
          Logger.debug("#{func_name}: creating a new computation object")

          updated_execution_record =
            execution_db_record
            |> Ecto.Changeset.change(revision: execution_db_record.revision + 1)
            |> Journey.Repo.update!()

          now = Journey.Utilities.curent_unix_time_sec()

          %Journey.Schema.Computation{
            id: Journey.Utilities.object_id("cmp", 10),
            execution_id: execution.id,
            name: step_name_string,
            scheduled_time: 0,
            start_time: now,
            end_time: nil,
            deadline: now + expires_after_seconds,
            result_code: :computing,
            ex_revision: updated_execution_record.revision
          }
          |> Journey.Repo.insert!()

        _existing_computation ->
          # A computation for this step already exists. Do not proceed.
          Logger.debug("#{func_name}: already computing or computed")

          {:error, :computation_exists}
      end
    end)
    |> case do
      {:ok, {:error, :computation_exists}} ->
        {:error, :computation_exists}

      {:ok, result} ->
        {:ok, result}
    end
  end

  def complete_computation_and_record_result(execution, computation, step_name, value) do
    func_name = "complete_computation_and_record_result[#{execution.id}][#{step_name}]"
    Logger.debug("#{func_name}: start")

    step_name_string = Atom.to_string(step_name)

    from(
      computation in Journey.Schema.Computation,
      where:
        computation.id == ^computation.id and computation.execution_id == ^execution.id and
          computation.name == ^step_name_string and
          computation.result_code == ^:computing
    )
    |> Journey.Repo.one()
    |> case do
      nil ->
        # The computation does not exist for some reason (e. g. the computation took too long, and has been marked as :expired).
        # Log and proceed. The result will simply be discarded.
        Logger.warn("#{func_name}: an incomlete computation #{computation.id} does not seem to exist")

      # TODO: replace this with something along the lines of what we have in mark_abandoned_computations_as_expired, so this update happens as part of one query.
      reloaded_computation ->
        reloaded_computation
        |> Ecto.Changeset.change(
          result_code: :computed,
          result_value: %{value: value},
          end_time: Journey.Utilities.curent_unix_time_sec()
        )
        |> Journey.Repo.update()

        Logger.debug("#{func_name}: computation updated, completed")
    end

    load(execution.id)
  end

  def mark_computation_as_failed(execution, computation, step_name, error_details) do
    error_details_printable =
      error_details
      |> inspect(pretty: true)
      |> String.slice(0, 200)

    func_name = "mark_computation_as_failed[#{execution.id}][#{step_name}]"

    Logger.debug("#{func_name}: start. error details: #{error_details_printable}")

    step_name_string = Atom.to_string(step_name)

    from(
      computation in Journey.Schema.Computation,
      where:
        computation.id == ^computation.id and computation.execution_id == ^execution.id and
          computation.name == ^step_name_string and
          computation.result_code == ^:computing
    )
    |> Journey.Repo.one()
    |> case do
      nil ->
        # The computation does not exist for some reason. Log and proceed. The result will simply be discarded.
        Logger.warn("#{func_name}: an incomlete computation does not seem to exist")

      reloaded_computation ->
        # TODO: replace this with something along the lines of what we have in mark_abandoned_computations_as_expired, so this update happens as part of one query.
        reloaded_computation
        |> Ecto.Changeset.change(
          result_code: :failed,
          error_details: error_details_printable,
          end_time: Journey.Utilities.curent_unix_time_sec()
        )
        |> Journey.Repo.update()

        Logger.debug("#{func_name}: computation marked as failed, completed")
    end

    load(execution.id)
  end

  def set_value(execution, step_name, value) do
    Logger.debug("set_value [#{execution.id}][#{step_name}]")

    {:ok, _result} =
      Journey.Repo.transaction(fn repo ->
        execution_db_record =
          from(ex in Journey.Schema.Execution,
            where: ex.id == ^execution.id,
            lock: "FOR UPDATE"
          )
          |> repo.one!()

        # Record a ":computed" computation for this value.

        updated_execution_record =
          execution_db_record
          |> Ecto.Changeset.change(revision: execution_db_record.revision + 1)
          |> Journey.Repo.update!()

        %Journey.Schema.Computation{
          id: Journey.Utilities.object_id("cmp", 10),
          execution_id: execution.id,
          name: Atom.to_string(step_name),
          scheduled_time: 0,
          start_time: Journey.Utilities.curent_unix_time_sec(),
          end_time: Journey.Utilities.curent_unix_time_sec(),
          result_code: :computed,
          result_value: %{value: value},
          ex_revision: updated_execution_record.revision
        }
        |> Journey.Repo.insert!()
      end)

    load(execution.id)
  end

  def load(execution, include_computations \\ true)

  def load(execution_id, include_computations) when is_binary(execution_id) do
    Logger.info("load[#{execution_id}]: reloading")

    Journey.Repo.get(Journey.Schema.Execution, execution_id)
    |> then(fn execution ->
      if include_computations do
        execution
        |> Journey.Repo.preload(:computations)
        |> cleanup_computations()
      else
        execution
      end
    end)
  end

  def load(execution, include_computations) when is_map(execution) do
    load(execution.id, include_computations)
  end

  def mark_abandoned_computations_as_expired() do
    # Find old abandoned computations, mark them as expired, and return them.
    now = Journey.Utilities.curent_unix_time_sec()

    {count, updated_items} =
      from(
        c in Journey.Schema.Computation,
        where: c.result_code == ^:computing and c.deadline < ^now,
        # where: c.result_code == ^:failed,
        select: c
      )
      |> Journey.Repo.update_all(set: [result_code: :expired])

    Logger.info("mark_abandoned_computations_as_expired: processed #{count} abandoned computations")

    updated_items
  end

  def get_executions_to_kick_off() do
    # computations that are
    # - scheduled, but whose status is nil (do this later, for timed tasks)
    # - computing, but haven't completed within their limit
  end

  defp cleanup_computations(execution) do
    updated_computations =
      execution.computations
      |> Enum.map(fn c ->
        # Replace computation name string with the corresponding atoms.
        %{c | name: String.to_atom(c.name)}
      end)
      |> Enum.map(fn c ->
        if c.result_value == nil do
          c
        else
          # Simplify result_value from %{"result": value} to just 'value'.
          %{"value" => value} = c.result_value
          %{c | result_value: value}
        end
      end)

    %{execution | computations: updated_computations}
  end
end
