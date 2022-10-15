defmodule Journey.Test.Lifetime do
  use ExUnit.Case

  require WaitForIt

  test "execute a basic process" do
    # Start process execution.
    execution =
      Journey.Test.UserJourney.itinerary()
      |> Journey.Process.start()

    assert execution

    # Set the value for the 1st step.
    execution =
      execution
      |> Journey.Execution.set_value(:user_id, "user1")

    assert execution

    # The remaining steps should promptly compute.
    wait_for_result_to_compute(execution, :morning_update)
    wait_for_result_to_compute(execution, :evening_check_in)
    wait_for_result_to_compute(execution, :user_lifetime_completed)
    wait_for_all_steps_to_be_completed(execution)
  end

  def wait_for_all_steps_to_be_completed(execution) do
    case WaitForIt.wait(
           Journey.Execution.reload(execution)
           |> Journey.Execution.get_unfilled_steps()
           |> Enum.count() == 0,
           timeout: 5_000,
           frequency: 1000
         ) do
      {:ok, _} ->
        true

      {:timeout, _timeout} ->
        {:ok, execution} = Journey.Execution.reload(execution)
        execution |> Journey.Execution.get_summary() |> IO.puts()
        assert false, "horoscope step never computed"
    end
  end

  #  defp find_computation(computations, step_name) do
  #    Enum.find(fn c -> c.name == step_name end)
  #  end

  defp wait_for_result_to_compute(execution, step_name) do
    case WaitForIt.wait(
           Journey.Execution.reload(execution)
           |> Journey.Execution.get_computation_status(step_name) ==
             :computed,
           timeout: 5_000,
           frequency: 1000
         ) do
      {:ok, _} ->
        true

      {:timeout, _timeout} ->
        execution = Journey.Execution.reload(execution)
        execution |> Journey.Execution.get_summary() |> IO.puts()
        assert false, "step '#{step_name}' never computed"
    end
  end
end
