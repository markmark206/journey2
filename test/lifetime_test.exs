defmodule Journey.Test.Lifetime do
  use ExUnit.Case
  require Logger

  require WaitForIt

  setup do
    {:ok, %{test_id: Journey.Utilities.object_id("tid")}}
  end

  test "execute a basic process", %{test_id: test_id} do
    # Start process execution.
    user_id = "user_basic_#{test_id}"

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
    wait_for_result_to_compute(execution, :morning_update, check_wait(), check_frequency())
    wait_for_result_to_compute(execution, :evening_check_in, check_wait(), check_frequency())

    wait_for_result_to_compute(
      execution,
      :user_lifetime_completed,
      check_wait(),
      check_frequency(),
      if(Journey.Test.UserJourney.fail?(), do: :failed, else: :computed)
    )

    wait_for_all_steps_to_be_completed(execution, check_wait(), check_frequency())

    execution =
      execution
      |> Journey.Execution.reload()

    one_year_ish = 60 * 60 * 24 * 365
    now = Journey.Utilities.curent_unix_time_sec()
    assert Journey.Execution.Queries.get_computation_status(execution, :started_at) == :computed
    assert Journey.Execution.Queries.get_computation(execution, :started_at).error_details == nil
    assert Journey.Execution.Queries.get_computation_value(execution, :started_at) <= now
    assert Journey.Execution.Queries.get_computation_value(execution, :started_at) >= now - one_year_ish

    assert Journey.Execution.Queries.get_computation_status(execution, :user_id) == :computed
    assert Journey.Execution.Queries.get_computation(execution, :user_id).error_details == nil
    assert Journey.Execution.Queries.get_computation_value(execution, :user_id) == user_id

    assert Journey.Execution.Queries.get_computation_status(execution, :morning_update) == :computed
    assert Journey.Execution.Queries.get_computation(execution, :morning_update).error_details == nil
    expected_morning_update_result = "morning update completed for user #{user_id}"
    assert Journey.Execution.Queries.get_computation_value(execution, :morning_update) == expected_morning_update_result

    assert Journey.Execution.Queries.get_computation_status(execution, :evening_check_in) == :computed
    assert Journey.Execution.Queries.get_computation(execution, :evening_check_in).error_details == nil
    expected_evening_checkin_result = "evening check in completed for user #{user_id}"

    assert Journey.Execution.Queries.get_computation_value(execution, :evening_check_in) ==
             expected_evening_checkin_result

    if Journey.Test.UserJourney.fail?() do
      assert Journey.Execution.Queries.get_computation_status(execution, :user_lifetime_completed) == :failed
      assert Journey.Execution.Queries.get_computation(execution, :user_lifetime_completed).error_details != nil
      assert Journey.Execution.Queries.get_computation_value(execution, :user_lifetime_completed) == nil
    else
      assert Journey.Execution.Queries.get_computation_status(execution, :user_lifetime_completed) == :computed
      assert Journey.Execution.Queries.get_computation(execution, :user_lifetime_completed).error_details == nil

      assert Journey.Execution.Queries.get_computation_value(execution, :user_lifetime_completed) == [
               "user lifetime completed for user #{user_id}",
               Enum.join(["#{user_id}", expected_morning_update_result, expected_evening_checkin_result], ", ")
             ]
    end

    Journey.Execution.sweep_and_revisit_expired_computations()
  end

  test "expired tasks", %{test_id: test_id} do
    # TODO: implement
    # excercise process.start() and have a plan that takes too long to process things.
    # what to do with execution that now have multiple computations for the same task.

    user_id = "user_abandoned_tasks_#{test_id}"

    # Start background sweep tasks. TODO: run this supervised / under OTP.
    base_delay_for_background_tasks_seconds = 2
    Journey.Process.kick_off_background_tasks(base_delay_for_background_tasks_seconds)

    # Start process execution.
    execution =
      Journey.Test.UserJourneyAbandonedSweeps.itinerary()
      |> Journey.Process.start()

    assert execution

    # Set the value for the 1st step.
    execution =
      execution
      |> Journey.Execution.set_value(:user_id, user_id)

    assert execution

    # The remaining steps should promptly compute.
    wait_for_result_to_compute(execution, :morning_update, 2_000, 100)
    wait_for_result_to_compute(execution, :evening_check_in, 2_000, 100)

    # The computation will eventually become expired.
    wait_for_result_to_compute(execution, :user_lifetime_completed, 30_000, 1_000, :expired, false)

    # The computation will eventually be retried, and become computed.
    wait_for_result_to_compute(execution, :user_lifetime_completed, 30_000, 1_000, :computed, true)

    # There should be two computations for :user_lifetime_completed at this point.
    assert execution
           |> Journey.Execution.reload()
           |> Journey.Execution.Queries.get_computations(:user_lifetime_completed)
           |> Enum.count() == 2
  end

  defp check_frequency() do
    if Journey.Test.UserJourney.slow?(), do: 2_000, else: 100
  end

  defp check_wait() do
    if Journey.Test.UserJourney.slow?(), do: 10_000, else: 2000
  end

  defp wait_for_all_steps_to_be_completed(execution, check_wait, check_frequency) do
    case WaitForIt.wait(
           Journey.Execution.reload(execution)
           |> Journey.Execution.names_of_steps_not_yet_fully_computed()
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

  defp wait_for_result_to_compute(
         execution,
         step_name,
         check_wait,
         check_frequency,
         expected_status \\ :computed,
         most_recent \\ true
       ) do
    Logger.info("why why why expected status #{expected_status}")

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

        most_recent_computation = Journey.Execution.Queries.get_most_recent_computation_status(execution, step_name)

        assert false,
               "step '#{step_name}' in '#{execution.process_id}' never became #{expected_status}, execution:\n#{inspect(execution, pretty: true)}, most recent task:\n#{inspect(most_recent_computation, pretty: true)}"
    end
  end
end