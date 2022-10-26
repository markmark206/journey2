defmodule Journey.Test.Lifetime do
  # use ExUnit.Case
  use Journey.RepoCase

  require Logger

  require WaitForIt

  setup do
    {:ok, %{test_id: Journey.Utilities.object_id("tid")}}
  end

  def testing_basic_process(test_id, slow, fail) do
    # Ecto.Adapters.SQL.Sandbox.unboxed_run(Journey.Repo, fn ->

    itinerary = Journey.Test.UserJourney.itinerary(slow, fail)
    Journey.Process.register_itinerary(itinerary)

    user_id = "user_basic_#{slow}_#{fail}_#{test_id}"

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

    execution =
      execution
      |> Journey.Execution.reload()

    execution_summary = Journey.Execution.get_summary(execution)
    Logger.info("test execution summary:\n#{execution_summary}")

    # end)
  end

  @tag timeout: 600_000
  test "execute a basic process (slow, force failure)", %{test_id: test_id} do
    # Ecto.Adapters.SQL.Sandbox.unboxed_run(Journey.Repo, fn ->
    testing_basic_process(test_id, true, true)
    # end)
  end

  @tag timeout: 600_000
  test "execute a basic process (fast, force failure)", %{test_id: test_id} do
    # Ecto.Adapters.SQL.Sandbox.unboxed_run(Journey.Repo, fn ->
    testing_basic_process(test_id, false, true)
    # end)
  end

  @tag timeout: 600_000
  test "execute a basic process (slow, success)", %{test_id: test_id} do
    # Ecto.Adapters.SQL.Sandbox.unboxed_run(Journey.Repo, fn ->
    testing_basic_process(test_id, true, false)
    # end)
  end

  @tag timeout: 600_000
  test "execute a basic process (fast, success)", %{test_id: test_id} do
    # Ecto.Adapters.SQL.Sandbox.unboxed_run(Journey.Repo, fn ->
    testing_basic_process(test_id, false, false)
    # end)
  end

  @tag timeout: 600_000
  test "abandoned / expired computation, recomputed, many of them", %{test_id: test_id} do
    # Ecto.Adapters.SQL.Sandbox.unboxed_run(Journey.Repo, fn ->
    Journey.Process.register_itinerary(Journey.Test.UserJourneyAbandonedSweeps.itinerary())

    # Start background sweep tasks. TODO: run this supervised / under OTP.
    task =
      Task.async(fn ->
        Journey.Execution.Daemons.delay_and_sweep_task(2)
      end)

    user_ids =
      for sequence <- 1..1 do
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
      wait_for_result_to_compute(execution, :morning_update, 10_000, 1000)
      wait_for_result_to_compute(execution, :evening_check_in, 10_000, 1000)

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

      %{name: _morning_or_evening_check, scheduled_time: 0, result_code: :computed, ex_revision: 3} = c3
      %{name: _morning_or_evening_check, scheduled_time: 0, result_code: :computed, ex_revision: 4} = c4

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

      Logger.info(
        "test: verified that execution #{execution.id} ends up with the expected number of completed computations."
      )

      execution
    end)

    Logger.info("test: shutting down background sweeper task.")
    Task.shutdown(task)
    Logger.info("test: shutting down background sweeper task... done.")

    # end)
  end

  @tag timeout: 600_000
  test "scheduled recurring tasks, recomputed", %{test_id: test_id} do
    # Ecto.Adapters.SQL.Sandbox.unboxed_run(Journey.Repo, fn ->
    user_id = "user_recurring_tasks_#{test_id}"

    # Start background sweep tasks. TODO: run this supervised / under OTP.
    task =
      Task.async(fn ->
        Journey.Execution.Daemons.delay_and_sweep_task(2)
      end)

    Journey.Process.register_itinerary(Journey.Test.UserJourneyScheduledRecurring.itinerary())

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

    # This function waits a bit, and then loads the execution and makes sure the execution looks as
    # we would expect at that moment in time.
    check_counts = fn _, {prev_computed_morning, prev_computed_evening} ->
      :timer.sleep(Journey.Utilities.seconds_until_the_end_of_next_minute() * 1000)

      for_one_task = fn task_id, prev_computed ->
        execution =
          execution
          |> Journey.Execution.reload()

        current_computed =
          execution
          |> Journey.Execution.Queries.get_sorted_computations_by_status(task_id, :computed)

        # We should now have more computed steps than last time.
        assert Enum.count(prev_computed) < Enum.count(current_computed),
               "unexpected number of computed tasks (#{Enum.count(current_computed)}), expecting more than #{Enum.count(prev_computed)}, execution: #{inspect(execution, pretty: true)}"

        current_scheduled =
          execution
          |> Journey.Execution.Queries.get_sorted_computations_by_status(task_id, :scheduled)

        current_computing =
          execution
          |> Journey.Execution.Queries.get_sorted_computations_by_status(task_id, :computing)

        # We should always have one computing or scheduled task.

        # There is a tiny window between before a new computation is scheduled, after one completes, so we might have a very rare false failure here.
        assert Enum.count(current_scheduled) + Enum.count(current_computing) == 1,
               "unexpected number of scheduled tasks, execution: #{inspect(execution, pretty: true)}"

        current_computed
      end

      current_computed_morning = for_one_task.(:morning_update, prev_computed_morning)
      current_computed_evening = for_one_task.(:evening_check_in, prev_computed_evening)
      {current_computed_morning, current_computed_evening}
    end

    # Check that the execution looks as we expect over a period of time.
    Enum.reduce(1..3, {[], []}, check_counts)
    # end)

    Logger.info("test: shutting down background sweeper task")
    Task.shutdown(task)
    Logger.info("test: shutting down background sweeper task... done.")
  end

  @tag timeout: 200_000
  test "just running background sweepers", %{test_id: _test_id} do
    Journey.Process.register_itinerary(Journey.Test.UserJourneyScheduledRecurring.itinerary())

    # Start background sweep tasks. TODO: run this supervised / under OTP.
    task =
      Task.async(fn ->
        Journey.Execution.Daemons.delay_and_sweep_task(2)
      end)

    Logger.info("waiting before exising...")
    :timer.sleep(40_000)
    Logger.info("... exiting")

    Logger.info("test: shutting down background sweeper task.")
    Task.shutdown(task)
    Logger.info("test: shutting down background sweeper task... done.")
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

  defp wait_for_result_to_compute(
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
