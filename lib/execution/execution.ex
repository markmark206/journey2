defmodule Journey.Execution do
  require Logger
  import Journey.Utilities, only: [f_name: 0]

  def new(process_id) do
    Journey.Execution.Store.create_new_execution_record(process_id)
  end

  @spec set_value(
          atom
          | %{:id => binary | %{:id => binary | map, optional(any) => any}, optional(any) => any},
          any,
          any
        ) :: atom | %{:computations => any, optional(any) => any}

  def set_value(execution, step, value) do
    execution
    |> Journey.Execution.Store.set_value(step, value)
    # |> Journey.Execution.Scheduler.kick_off_or_schedule_unblocked_steps_if_any()
    |> Journey.Execution.Scheduler2.advance()
  end

  def reload(execution) do
    # Reload an execution from the db.
    execution |> Journey.Execution.Store.load()
  end

  def get_summary(execution) do
    "execution summary. TODO: implement '#{execution.id}'"
  end
end
