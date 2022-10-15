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
  def create_initial_record(process_id) do
    Logger.debug("create_initial_record")

    {:ok, execution_db_record} =
      %Journey.Schema.Execution{
        process_id: process_id
      }
      |> Journey.Repo.insert()

    execution_db_record
    |> Journey.Repo.preload([:computations])
  end

  def set_value(execution, step_name, value) do
    Logger.debug("set_value [#{execution.id}][#{step_name}]")
    # inside a transaction, create a computation, and spin up any unblocked computations.

    %Journey.Schema.Computation{
      id: Journey.Utilities.object_id("cmp", 10),
      execution_id: execution.id,
      name: Atom.to_string(step_name),
      scheduled_time: 0,
      start_time: Journey.Utilities.curent_unix_time_sec(),
      end_time: Journey.Utilities.curent_unix_time_sec(),
      # revision: 0,
      result_code: :computed,
      result_value: %{value: value}
    }
    |> Journey.Repo.insert()

    load(execution.id)
  end

  def load(execution_id) when is_binary(execution_id) do
    Journey.Repo.get(Journey.Schema.Execution, execution_id)
    |> Journey.Repo.preload(:computations)
    |> convert_computation_task_names_to_atoms()
  end

  def load(execution) when is_map(execution) do
    load(execution.id)
  end

  defp convert_computation_task_names_to_atoms(execution) do
    updated_computations =
      execution.computations
      |> Enum.map(fn c ->
        %{c | name: String.to_atom(c.name)}
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
