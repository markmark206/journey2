defmodule Journey.Test.ScheduledRecurring do
  use Journey.RepoCase

  require Logger

  setup do
    {:ok, %{test_id: Journey.Utilities.object_id("tid")}}
  end

  def check_task_progress(execution, task_id, prev_computed) do
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

  def wait_and_check_results(execution, prev_computed_morning, prev_computed_evening) do
    :timer.sleep(Journey.Utilities.seconds_until_the_end_of_next_minute() * 1000)

    current_computed_morning = check_task_progress(execution, :morning_update, prev_computed_morning)
    current_computed_evening = check_task_progress(execution, :evening_check_in, prev_computed_evening)
    {current_computed_morning, current_computed_evening}
  end

  @tag timeout: 600_000
  test "scheduled recurring tasks, recomputed", %{test_id: test_id} do
    # Ecto.Adapters.SQL.Sandbox.unboxed_run(Journey.Repo, fn ->
    user_id = "user_recurring_tasks_#{test_id}"

    Journey.Test.Plans.ScheduledRecurring.itinerary()
    |> Journey.Process.register_itinerary()

    # Start process execution.
    execution =
      Journey.Test.Plans.ScheduledRecurring.itinerary()
      |> Journey.Process.start()

    assert execution

    # Set the value for the 1st step.
    execution =
      execution
      |> Journey.Execution.set_value(:user_id, user_id)
      |> Journey.Execution.set_value(:morning_schedule_setting, 10)
      |> Journey.Execution.set_value(:evening_schedule_setting, 30)

    assert execution

    # This function waits a bit, and then loads the execution and makes sure the execution looks as
    # we would expect at that moment in time.

    # Check that the execution looks as we expect over a period of time.
    Enum.reduce(1..3, {[], []}, fn _, {prev_computed_morning, prev_computed_evening} ->
      wait_and_check_results(execution, prev_computed_morning, prev_computed_evening)
    end)

    # end)
  end
end
