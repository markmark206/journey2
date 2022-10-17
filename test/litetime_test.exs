defmodule Journey.Test.Lifetime do
  use ExUnit.Case

  require WaitForIt

  setup do
    {:ok, %{user_id: Journey.Utilities.object_id("userid")}}
  end

  test "execute a basic process", %{user_id: user_id} do
    # Start process execution.
    execution =
      Journey.Test.UserJourney.itinerary()
      |> Journey.Process.start()

    assert execution

    if Journey.Test.UserJourney.slow?() do
      :timer.sleep(1000)
    end

    # Set the value for the 1st step.
    execution =
      execution
      |> Journey.Execution.set_value(:user_id, user_id)

    assert execution

    # The remaining steps should promptly compute.
    wait_for_result_to_compute(execution, :morning_update)
    wait_for_result_to_compute(execution, :evening_check_in)

    wait_for_result_to_compute(
      execution,
      :user_lifetime_completed,
      if(Journey.Test.UserJourney.fail?(), do: :failed, else: :computed)
    )

    wait_for_all_steps_to_be_completed(execution)

    execution =
      execution
      |> Journey.Execution.reload()

    one_year_ish = 60 * 60 * 24 * 365
    now = Journey.Utilities.curent_unix_time_sec()
    assert Journey.Execution.get_computation_status(execution, :started_at) == :computed
    assert Journey.Execution.get_computation(execution, :started_at).error_details == nil
    assert Journey.Execution.get_computation_value(execution, :started_at) <= now
    assert Journey.Execution.get_computation_value(execution, :started_at) >= now - one_year_ish

    assert Journey.Execution.get_computation_status(execution, :user_id) == :computed
    assert Journey.Execution.get_computation(execution, :user_id).error_details == nil
    assert Journey.Execution.get_computation_value(execution, :user_id) == user_id

    assert Journey.Execution.get_computation_status(execution, :morning_update) == :computed
    assert Journey.Execution.get_computation(execution, :morning_update).error_details == nil
    expected_morning_update_result = "morning update completed for user #{user_id}"
    assert Journey.Execution.get_computation_value(execution, :morning_update) == expected_morning_update_result

    assert Journey.Execution.get_computation_status(execution, :evening_check_in) == :computed
    assert Journey.Execution.get_computation(execution, :evening_check_in).error_details == nil
    expected_evening_checkin_result = "evening check in completed for user #{user_id}"
    assert Journey.Execution.get_computation_value(execution, :evening_check_in) == expected_evening_checkin_result

    if Journey.Test.UserJourney.fail?() do
      assert Journey.Execution.get_computation_status(execution, :user_lifetime_completed) == :failed
      assert Journey.Execution.get_computation(execution, :user_lifetime_completed).error_details != nil
      assert Journey.Execution.get_computation_value(execution, :user_lifetime_completed) == nil
    else
      assert Journey.Execution.get_computation_status(execution, :user_lifetime_completed) == :computed
      assert Journey.Execution.get_computation(execution, :user_lifetime_completed).error_details == nil

      assert Journey.Execution.get_computation_value(execution, :user_lifetime_completed) == [
               "user lifetime completed for user #{user_id}",
               Enum.join(["#{user_id}", expected_morning_update_result, expected_evening_checkin_result], ", ")
             ]
    end
  end

  defp check_frequency() do
    if Journey.Test.UserJourney.slow?(), do: 2_000, else: 200
  end

  defp check_wait() do
    if Journey.Test.UserJourney.slow?(), do: 10_000, else: 2000
  end

  defp wait_for_all_steps_to_be_completed(execution) do
    case WaitForIt.wait(
           Journey.Execution.reload(execution)
           |> Journey.Execution.names_of_steps_not_yet_fully_computed()
           |> Enum.count() == 0,
           timeout: check_wait(),
           frequency: check_frequency()
         ) do
      {:ok, _} ->
        true

      {:timeout, _timeout} ->
        {:ok, execution} = Journey.Execution.reload(execution)
        execution |> Journey.Execution.get_summary() |> IO.puts()
        assert false, "horoscope step never computed"
    end
  end

  defp wait_for_result_to_compute(execution, step_name, expected_status \\ :computed) do
    case WaitForIt.wait(
           Journey.Execution.reload(execution)
           |> Journey.Execution.get_computation_status(step_name) ==
             expected_status,
           timeout: check_wait(),
           frequency: check_frequency()
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
