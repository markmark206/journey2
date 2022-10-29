defmodule Journey.Test.AbandonedAndExpired do
  # use ExUnit.Case
  use Journey.RepoCase

  import Journey.Test.Helpers

  require Logger

  setup do
    {:ok, %{test_id: Journey.Utilities.object_id("tid")}}
  end

  @tag timeout: 600_000
  test "abandoned / expired computation, recomputed, many of them", %{test_id: test_id} do
    # Ecto.Adapters.SQL.Sandbox.unboxed_run(Journey.Repo, fn ->
    Journey.Test.Plans.AbandonedSweeps.itinerary()
    |> Journey.Process.register_itinerary()

    # Start background sweep tasks. TODO: run this supervised / under OTP.
    # task =
    #   Task.async(fn ->
    #     Journey.Execution.Daemons.delay_and_sweep_task(2)
    #   end)

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
          Journey.Test.Plans.AbandonedSweeps.itinerary()
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

    # Logger.info("test: shutting down background sweeper task.")
    # Task.shutdown(task)
    # Logger.info("test: shutting down background sweeper task... done.")

    # end)
  end
end
