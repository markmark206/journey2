defmodule Journey.Test.Lifetime do
  # use ExUnit.Case
  use Journey.RepoCase
  import Ecto.Query

  require Logger

  require WaitForIt

  setup do
    {:ok, %{test_id: Journey.Utilities.object_id("tid")}}
  end

  test "execute a basic process", %{test_id: test_id} do
    #    Ecto.Adapters.SQL.Sandbox.unboxed_run(Journey.Repo, fn ->
    for slow <- [true, false] do
      for fail <- [true, false] do
        user_id = "user_basic_#{slow}_#{fail}_#{test_id}"

        itinerary = Journey.Test.UserJourney.itinerary(slow, fail)
        Journey.Process.register_itinerary(itinerary)

        execution =
          itinerary
          |> Journey.Process.start()

        assert execution

        if slow do
          :timer.sleep(1000)
        end

        # Set the value for the 1st step.
        execution =
          execution
          |> Journey.Execution.set_value(:user_id, user_id)

        assert execution

        # The remaining steps should promptly compute.
        wait_for_result_to_compute(execution, :morning_update, check_wait(slow), check_frequency(slow))
        wait_for_result_to_compute(execution, :evening_check_in, check_wait(slow), check_frequency(slow))

        wait_for_result_to_compute(
          execution,
          :user_lifetime_completed,
          check_wait(slow),
          check_frequency(slow),
          if(fail, do: :failed, else: :computed)
        )

        wait_for_all_steps_to_be_completed(execution, check_wait(slow), check_frequency(slow))

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

        expected_morning_update_result =
          "Elixir.Journey.Test.UserJourney_slow_#{slow}_fail_#{fail}.send_morning_update for user #{user_id}"

        assert Journey.Execution.Queries.get_computation_value(execution, :morning_update) ==
                 expected_morning_update_result

        assert Journey.Execution.Queries.get_computation_status(execution, :evening_check_in) == :computed
        assert Journey.Execution.Queries.get_computation(execution, :evening_check_in).error_details == nil

        expected_evening_checkin_result =
          "Elixir.Journey.Test.UserJourney_slow_#{slow}_fail_#{fail}.send_evening_check_in for user #{user_id}"

        assert Journey.Execution.Queries.get_computation_value(execution, :evening_check_in) ==
                 expected_evening_checkin_result

        if fail do
          assert Journey.Execution.Queries.get_computation_status(execution, :user_lifetime_completed) == :failed
          assert Journey.Execution.Queries.get_computation(execution, :user_lifetime_completed).error_details != nil
          assert Journey.Execution.Queries.get_computation_value(execution, :user_lifetime_completed) == nil
        else
          assert Journey.Execution.Queries.get_computation_status(execution, :user_lifetime_completed) == :computed
          assert Journey.Execution.Queries.get_computation(execution, :user_lifetime_completed).error_details == nil

          assert Journey.Execution.Queries.get_computation_value(execution, :user_lifetime_completed) == [
                   "Elixir.Journey.Test.UserJourney_slow_#{slow}_fail_#{fail}.user_lifetime_completed for user #{user_id}",
                   Enum.join(["#{user_id}", expected_morning_update_result, expected_evening_checkin_result], ", ")
                 ]
        end
      end
    end

    #    end)
  end

  @tag timeout: 200_000
  test "expired computation, recomputed", %{test_id: test_id} do
    # Ecto.Adapters.SQL.Sandbox.unboxed_run(Journey.Repo, fn ->
    # TODO: implement
    # excercise process.start() and have a plan that takes too long to process things.
    # what to do with execution that now have multiple computations for the same task.

    Journey.Process.register_itinerary(Journey.Test.UserJourneyAbandonedSweeps.itinerary())

    # Start background sweep tasks. TODO: run this supervised / under OTP.
    base_delay_for_background_tasks_seconds = 2
    Journey.Process.kick_off_background_tasks(base_delay_for_background_tasks_seconds)

    user_ids =
      for sequence <- 1..200 do
        "user_abandoned_tasks_#{test_id}_#{sequence}"
      end

    # Kick off all the executions.
    executions_and_users =
      user_ids
      |> Enum.map(fn user_id ->
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
        {execution, user_id}
      end)

    # Collect amd verify the results from every execution
    executions_and_users
    |> Enum.map(fn {execution, user_id} ->
      # The remaining steps should promptly compute.
      wait_for_result_to_compute(execution, :morning_update, 2_000, 100)
      wait_for_result_to_compute(execution, :evening_check_in, 2_000, 100)

      # The computation will eventually become expired.
      wait_for_result_to_compute(execution, :user_lifetime_completed, 30_000, 1_000, :expired, false)

      # The computation will eventually be retried, and become computed.
      wait_for_result_to_compute(execution, :user_lifetime_completed, 30_000, 1_000, :computed, true)

      execution = execution |> Journey.Execution.reload()
      # There should be two computations for :user_lifetime_completed at this point.
      assert execution
             |> Journey.Execution.Queries.get_computations(:user_lifetime_completed)
             |> Enum.count() == 2

      assert execution.revision == 6, "execution #{execution.id} does not have the expected number of revisions"

      assert execution.computations |> Enum.count() == 6

      # Verify that computations look like what we expect.
      [
        c1,
        c2,
        c3,
        c4,
        c5,
        c6
      ] = execution.computations

      # Keeping pattern matching for individual computations separate, so it's easier to investigate failures.
      %{name: :started_at, result_code: :computed, scheduled_time: 0, error_details: nil, ex_revision: 1} = c1

      %{
        name: :user_id,
        result_code: :computed,
        scheduled_time: 0,
        error_details: nil,
        result_value: ^user_id,
        ex_revision: 2
      } = c2

      %{name: :morning_update, scheduled_time: 0, result_code: :computed, ex_revision: 3} = c3
      %{name: :evening_check_in, scheduled_time: 0, result_code: :computed, ex_revision: 4} = c4

      %{
        name: :user_lifetime_completed,
        scheduled_time: 0,
        result_code: :expired,
        error_details: nil,
        result_value: nil,
        ex_revision: 5
      } = c5

      %{
        name: :user_lifetime_completed,
        scheduled_time: 0,
        result_code: :computed,
        error_details: nil,
        ex_revision: 6
      } = c6

      execution
    end)

    # end)
  end

  @tag timeout: 600_000
  test "scheduled recurring tasks, recomputed", %{test_id: test_id} do
    Ecto.Adapters.SQL.Sandbox.unboxed_run(Journey.Repo, fn ->
      user_id = "user_recurring_tasks_#{test_id}"

      Journey.Process.register_itinerary(Journey.Test.UserJourneyScheduledRecurring.itinerary())

      # Start background sweep tasks. TODO: run this supervised / under OTP.
      base_delay_for_background_tasks_seconds = 2
      Journey.Process.kick_off_background_tasks(base_delay_for_background_tasks_seconds)

      # Start process execution.
      execution =
        Journey.Test.UserJourneyScheduledRecurring.itinerary()
        |> Journey.Process.start()

      assert execution

      # Set the value for the 1st step.
      execution =
        execution
        |> Journey.Execution.set_value(:user_id, user_id)

      assert execution

      # The remaining steps should promptly compute.
      wait_for_result_to_compute(execution, :morning_update, 2_000, 100, :scheduled)
      # wait_for_result_to_compute(execution, :evening_check_in, 2_000, 100, :scheduled)

      # The scheduled computations will eventually become computed.
      # TODO: implemennt

      # The final computation will eventually become computed.
      # TODO: implemennt
      # wait_for_result_to_compute(execution, :user_lifetime_completed, 30_000, 1_000, :computed, true)

      # The schedulable steps will stop getting scheduled.
      # TODO: implemennt

      Logger.info("waiting a while before exising test...")
      :timer.sleep(300_000)
      Logger.info("... test exising")
    end)
  end

  @tag timeout: 600_000
  test "just running background sweepers", %{test_id: test_id} do
    # Start background sweep tasks. TODO: run this supervised / under OTP.
    Journey.Process.register_itinerary(Journey.Test.UserJourneyScheduledRecurring.itinerary())

    base_delay_for_background_tasks_seconds = 2
    Journey.Process.kick_off_background_tasks(base_delay_for_background_tasks_seconds)

    Logger.info("waiting a while before exising test...")
    :timer.sleep(300_000)
    Logger.info("... test exising")
  end

  defp check_frequency(slow) do
    if slow, do: 2_000, else: 100
  end

  defp check_wait(slow) do
    if slow, do: 10_000, else: 2000
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

        computation = Journey.Execution.Queries.get_computation(execution, step_name, most_recent)

        assert false,
               "step '#{step_name}' in '#{execution.process_id}' never became #{expected_status}, execution:\n#{inspect(execution, pretty: true)}, computation:\n#{inspect(computation, pretty: true)}"
    end
  end
end
