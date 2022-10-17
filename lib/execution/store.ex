defmodule Journey.Execution.Store do
  @moduledoc false

  require Logger
  import Ecto.Query

  # def get(execution_id) do
  #   Logger.debug("get: #{execution_id}")

  #   computations =
  #     from(
  #       c in Journey.Schema.Computation,
  #       where: c.execution_id == ^execution_id,
  #       select: c
  #     )
  #     |> Journey.Repo.all()
  #     |> Enum.map(fn c ->
  #       c
  #       |> Map.delete(:__meta__)
  #       |> Map.delete(:__struct__)
  #     end)

  #   # |> Enum.reduce(%{}, fn c, acc -> Map.put(acc, c.name)

  #   Journey.Repo.get!(Journey.ExecutionDbRecord, execution_id)
  #   |> Map.get(:execution_data)
  #   |> Map.put("computations", computations)
  # end

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

  # defp test_only_create_a_computation_record(execution, step_name) do
  #   # If we ever need to create a rogue computation record, to help us test how we handle this, we can use this function.
  #   # This function should not be called outside of tests.

  #   :test = Mix.env()

  #   %Journey.Schema.Computation{
  #     id: Journey.Utilities.object_id("cmp", 10),
  #     execution_id: execution.id,
  #     name: Atom.to_string(step_name),
  #     scheduled_time: 0,
  #     start_time: Journey.Utilities.curent_unix_time_sec(),
  #     result_code: :computing
  #   }
  #   |> Journey.Repo.insert()
  # end

  def create_new_computation_record_if_one_doesnt_exist_lock(execution, step_name) when is_atom(step_name) do
    # Create a new computation record. If one already exists, tell the caller.

    func_name = "create_new_computation_record_if_one_doesnt_exist_lock[#{execution.id}.#{step_name}]"
    Logger.debug("#{func_name}: starting")

    # If we want to test how the code handles computation records that already exist, uncomment this code, for test use only.
    # test_only_create_a_computation_record(execution, step_name)

    step_name_string = Atom.to_string(step_name)

    Journey.Repo.transaction(fn repo ->
      execution_db_record =
        from(ex in Journey.Schema.Execution,
          where: ex.id == ^execution.id,
          lock: "FOR UPDATE"
        )
        |> repo.one!()

      # |> IO.inspect(label: "chicken existing execution record for update")

      from(
        computation in Journey.Schema.Computation,
        where: computation.execution_id == ^execution.id and computation.name == ^step_name_string
      )
      |> Journey.Repo.one()
      |> case do
        nil ->
          # Record a ":computing" computation for this.
          # When executing on multiple hosts or processes, there a chance of duplicate records.
          Logger.debug("#{func_name}: creating a new computation object")

          updated_execution_record =
            execution_db_record
            |> Ecto.Changeset.change(revision: execution_db_record.revision + 1)
            |> Journey.Repo.update!()

          # |> IO.inspect(label: "updated execution record with new revision")

          %Journey.Schema.Computation{
            id: Journey.Utilities.object_id("cmp", 10),
            execution_id: execution.id,
            name: step_name_string,
            scheduled_time: 0,
            start_time: Journey.Utilities.curent_unix_time_sec(),
            end_time: nil,
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

        # {:error, :computation_exists} ->
        #  {:error, :computation_exists}
    end
  end

  def create_new_computation_record_if_one_doesnt_exist(execution, step_name) when is_atom(step_name) do
    # Create a new computation record. If one already exists, tell the caller.

    func_name = "create_new_computation_record_if_one_doesnt_exist[#{execution.id}.#{step_name}]"
    Logger.debug("#{func_name}: starting")

    # If we want to test how the code handles computation records that already exist, uncomment this code, for test use only.
    # test_only_create_a_computation_record(execution, step_name)

    step_name_string = Atom.to_string(step_name)

    query =
      from(
        computation in Journey.Schema.Computation,
        where: computation.execution_id == ^execution.id and computation.name == ^step_name_string
      )

    query
    |> Journey.Repo.one()
    |> case do
      nil ->
        # To *reduce* (not eliminate) the likelihood of duplicate computations, check again after a [random] bit.
        # TODO: replace this with a more robust mechanism of SELECT FOR UPDATE on the execution record.
        :timer.sleep(round(500.0 * :rand.uniform()))

        query
        |> Journey.Repo.one()

      existing_computation ->
        existing_computation
    end
    |> case do
      nil ->
        # Record a ":computing" computation for this.
        # When executing on multiple hosts or processes, there a chance of duplicate records.
        Logger.debug("#{func_name}: creating a new computation object")

        %Journey.Schema.Computation{
          id: Journey.Utilities.object_id("cmp", 10),
          execution_id: execution.id,
          name: step_name_string,
          scheduled_time: 0,
          start_time: Journey.Utilities.curent_unix_time_sec(),
          end_time: nil,
          result_code: :computing
        }
        |> Journey.Repo.insert()

      _existing_computation ->
        # A computation for this step already exists. Do not proceed.
        Logger.debug("#{func_name}: already computing or computed")

        {:error, :computation_exists}
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
        # The computation does not exist for some reason. Log and proceed. The result will simply be discarded.
        Logger.warn("#{func_name}: an incomlete computation does not seem to exist")

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
    # inside a transaction, create a computation, and spin up any unblocked computations.

    # step_name_string = Atom.to_string(step_name)

    {:ok, _result} =
      Journey.Repo.transaction(fn repo ->
        execution_db_record =
          from(ex in Journey.Schema.Execution,
            where: ex.id == ^execution.id,
            lock: "FOR UPDATE"
          )
          |> repo.one!()

        # Record a ":computing" computation for this.
        # When executing on multiple hosts or processes, there a chance of duplicate records.

        updated_execution_record =
          execution_db_record
          |> Ecto.Changeset.change(revision: execution_db_record.revision + 1)
          |> Journey.Repo.update!()

        # |> IO.inspect(label: "updated execution record with new revision")

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

  def load(execution_id) when is_binary(execution_id) do
    Logger.info("load[#{execution_id}]: reloading")

    Journey.Repo.get(Journey.Schema.Execution, execution_id)
    |> Journey.Repo.preload(:computations)
    |> cleanup_computations()

    # |> IO.inspect(label: "reloaded execution")
  end

  def load(execution) when is_map(execution) do
    load(execution.id)
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

  # @spec start_computation(String.t(), atom()) :: {atom(), map()}
  # def start_computation(execution_id, step_name) do
  #   Logger.error("recording start_computation, execution '#{execution_id}' / '#{step_name}'")
  #   # find an existing computation, and
  #   # Journey.Schema.Computation
  #   {:ok, result} =
  #     Journey.Repo.transaction(fn repo ->
  #       from(i in Journey.Schema.Computation,
  #         where: i.execution_id == ^execution_id and i.name == ^Atom.to_string(step_name)
  #       )
  #       |> repo.one()
  #       |> case do
  #         nil ->
  #           # no existing computation record. Create one.
  #           %Journey.Schema.Computation{
  #             id: Journey.Utilities.object_id("cmp", 10),
  #             execution_id: execution_id,
  #             name: Atom.to_string(step_name),
  #             scheduled_time: 0,
  #             start_time: Journey.Utilities.curent_unix_time_ms(),
  #             end_time: 0,
  #             revision: 0,
  #             result_code: nil,
  #             result_value: %{}
  #           }
  #           |> Journey.Repo.insert()
  #           |> case do
  #             {:ok, computation_record} ->
  #               {:ok, computation_record}

  #             {:error, changeset} ->
  #               Logger.error(
  #                 "unable to insert a computation record, #{inspect(changeset, pretty: true)}"
  #               )
  #           end

  #         computation_record ->
  #           # it looks like we already have a computation record. was the computation started on another host?
  #           # is it started but not yet completed? was it started too long ago? revisions?
  #           Logger.error(
  #             "start_computation: a computation record already exists, #{inspect(computation_record, pretty: true)}"
  #           )

  #           {:error, :computation_record_already_exists}
  #       end
  #     end)

  #   {:ok, result}
  # end

  # @spec end_computation(String.t(), atom(), atom(), map()) :: {atom(), map()}
  # def end_computation(execution_id, step_name, result_code, result) do
  #   Logger.error("recording end_computation, execution '#{execution_id}' / '#{step_name}'")
  #   # find an existing computation, and
  #   # Journey.Schema.Computation
  #   {:ok, result} =
  #     Journey.Repo.transaction(fn repo ->
  #       from(i in Journey.Schema.Computation,
  #         where: i.execution_id == ^execution_id and i.name == ^Atom.to_string(step_name)
  #       )
  #       |> repo.one()
  #       |> case do
  #         nil ->
  #           # no existing computation record. this is problematic. handle.
  #           {:error, :no_such_computation}

  #         computation_record ->
  #           computation_record
  #           |> Ecto.Changeset.change(
  #             end_time: Journey.Utilities.curent_unix_time_ms(),
  #             result_code: result_code,
  #             result_value: %{result: result}
  #           )
  #           |> Journey.Repo.update()
  #           |> case do
  #             {:ok, computation_record} ->
  #               {:ok, computation_record}

  #             {:error, changeset} ->
  #               Logger.error(
  #                 "unable to insert a computation record, #{inspect(changeset, pretty: true)}"
  #               )
  #           end
  #       end
  #     end)

  #   Logger.error(
  #     "end_computation: transaction completed. result: #{inspect(result, pretty: true)}"
  #   )

  #   {:ok, result}
  # end

  # @spec update_value(String.t(), atom(), atom(), any) :: {atom(), Journey.Execution.t()}
  # def update_value(execution_id, step_name, expected_status, value) do
  #   Logger.debug("update_value: #{execution_id}")

  #   {:ok, result} =
  #     Journey.Repo.transaction(fn repo ->
  #       execution_db_record =
  #         from(i in Journey.ExecutionDbRecord,
  #           where: i.id == ^execution_id,
  #           lock: "FOR UPDATE"
  #         )
  #         |> repo.one!()

  #       execution =
  #         Journey.ExecutionDbRecord.convert_to_execution_struct!(
  #           execution_db_record.execution_data
  #         )

  #       record_status = execution[:values][step_name].status

  #       # TODO markmark: update the value of the corresponding task.
  #       case expected_status do
  #         s when s in [record_status, :any] ->
  #           old_values = execution.values
  #           new_values = Map.put(old_values, step_name, value)
  #           new_execution = Map.put(execution, :values, new_values)
  #           new_execution = %{new_execution | save_version: new_execution.save_version + 1}

  #           execution_db_record
  #           |> Ecto.Changeset.change(execution_data: new_execution)
  #           |> repo.update!()

  #           {:ok, new_execution}

  #         _ ->
  #           repo.rollback({:not_updated_due_to_current_status, execution})
  #       end
  #     end)

  #   result
  # end
end
