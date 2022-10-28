defmodule Journey.Test.Helpers do
  use ExUnit.Case

  require Logger
  require WaitForIt

  import Journey.Utilities, only: [f_name: 0]

  def wait_for_all_steps_to_be_completed(execution, check_wait, check_frequency) do
    case WaitForIt.wait(
           Journey.Execution.reload(execution)
           |> Journey.Execution.Scheduler2.names_of_immediate_steps_not_yet_fully_computed()
           |> Enum.count() == 0,
           timeout: check_wait,
           frequency: check_frequency
         ) do
      {:ok, _} ->
        true

      {:timeout, _timeout} ->
        {:ok, execution} = Journey.Execution.reload(execution)
        execution |> Journey.Execution.get_summary() |> IO.puts()
        assert false, "`#{execution.process_id}` never reached completed state"
    end
  end

  def wait_for_result_to_compute(
        execution,
        step_name,
        check_wait,
        check_frequency,
        expected_status \\ :computed,
        most_recent \\ true
      ) do
    case WaitForIt.wait(
           Journey.Execution.reload(execution)
           |> Journey.Execution.Queries.get_computation_status(step_name, most_recent) ==
             expected_status,
           timeout: check_wait,
           frequency: check_frequency
         ) do
      {:ok, _} ->
        true

      {:timeout, _timeout} ->
        execution = Journey.Execution.reload(execution)
        execution |> Journey.Execution.get_summary() |> IO.puts()

        computation = Journey.Execution.Queries.get_computation(execution, step_name, most_recent)

        assert false,
               "step '#{step_name}' in '#{execution.process_id}' never became #{expected_status}, execution:\n#{inspect(execution, pretty: true)}, computation:\n#{inspect(computation, pretty: true)}"
    end
  end
end
