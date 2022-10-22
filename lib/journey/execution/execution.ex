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
    prefix = "#{f_name()}[#{execution.id}][#{step}]"
    Logger.info("#{prefix}: start")

    execution
    |> Journey.Execution.Store.set_value(step, value)
    |> Journey.Execution.Scheduler2.advance()
    |> tap(fn _ -> Logger.info("#{prefix}: done") end)
  end

  def reload(execution) do
    # Reload an execution from the db.
    execution |> Journey.Execution.Store.load()
  end

  defp conditional_timestamp(epoch_seconds) do
    if epoch_seconds != nil and epoch_seconds > 0 do
      "#{Journey.Utilities.epoch_to_timestamp(epoch_seconds)} (#{epoch_seconds})"
    else
      0
    end
  end

  defp computation_summary(computation) do
    """
    Revision #{computation.ex_revision}: '#{computation.id}' / '#{computation.name}:'
      Result: '#{computation.result_code}'
      Started at: #{conditional_timestamp(computation.start_time)}
      Ended at: #{conditional_timestamp(computation.end_time)}
      Deadline: #{conditional_timestamp(computation.deadline)}).
      Scheduled for: #{conditional_timestamp(computation.scheduled_time)}
    """
  end

  defp computations_summary(computations) do
    computations
    |> Enum.map(&computation_summary/1)
  end

  def get_summary(execution) do
    """
    # Execution Summary
    ID: #{execution.id}
    Process: #{execution.process_id}
    Revisions: #{execution.revision}
    Created at: #{conditional_timestamp(execution.inserted_at)}
    Last updated at: #{conditional_timestamp(execution.updated_at)}
    Computations:\n#{execution.computations |> computations_summary() |> Enum.map_join("\n", fn c -> "* #{c}" end)}
    """
  end
end
