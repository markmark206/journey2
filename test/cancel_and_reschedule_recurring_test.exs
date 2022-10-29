defmodule Journey.Test.CancelAndRescheduleRecurring do
  use Journey.RepoCase
  import Journey.Schema.Computation, only: [str_summary: 1]

  require Logger

  setup do
    {:ok, %{test_id: Journey.Utilities.object_id("tid")}}
  end

  def get_task_computations(execution, task_id) do
    execution =
      execution
      |> Journey.Execution.reload()

    computed =
      execution
      |> Journey.Execution.Queries.get_sorted_computations_by_status(task_id, :computed)

    scheduled =
      execution
      |> Journey.Execution.Queries.get_sorted_computations_by_status(task_id, :scheduled)

    computing =
      execution
      |> Journey.Execution.Queries.get_sorted_computations_by_status(task_id, :computing)

    {execution, computed, scheduled, computing}
  end

  def check_task_progress(execution, task_id, prev_computed) do
    execution =
      execution
      |> Journey.Execution.reload()

    {execution, current_computed, current_scheduled, current_computing} = get_task_computations(execution, task_id)

    # We should now have more computed steps than last time.
    assert Enum.count(prev_computed) < Enum.count(current_computed),
           "unexpected number of computed tasks (#{Enum.count(current_computed)}), expecting more than #{Enum.count(prev_computed)}, execution: #{inspect(execution, pretty: true)}"

    # We should always have one computing or scheduled task.
    # There is a tiny window between before a new computation is scheduled, after one completes, so we might have a very rare false failure here.
    assert Enum.count(current_scheduled) + Enum.count(current_computing) == 1,
           "unexpected number of scheduled tasks, execution: #{inspect(execution, pretty: true)}"

    {current_computed, current_scheduled, current_computing}
  end

  def wait_and_check_results(execution, prev_computed_morning, prev_computed_evening) do
    :timer.sleep(Journey.Utilities.seconds_until_the_end_of_next_minute() * 1000)

    {current_computed_morning, _, _} = check_task_progress(execution, :morning_update, prev_computed_morning)
    {current_computed_evening, _, _} = check_task_progress(execution, :evening_check_in, prev_computed_evening)
    {current_computed_morning, current_computed_evening}
  end

  @tag timeout: 600_000
  test "recurring task: cancel and reschedule", %{test_id: test_id} do
    # _task =
    #   Task.async(fn ->
    #     Journey.Execution.Daemons.delay_and_sweep_task(3)
    #   end)

    #    Ecto.Adapters.SQL.Sandbox.unboxed_run(Journey.Repo, fn ->
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

    assert execution

    # Wait a bit, and make sure no computations have been scheduled.
    :timer.sleep(2000)
    {execution, [], [], []} = get_task_computations(execution, :morning_update)
    assert execution

    {execution, [], [], []} = get_task_computations(execution, :evening_update)
    assert execution

    # unblock morning updates and make sure we now have 1 scheduled task.
    execution =
      execution
      |> Journey.Execution.set_value(:morning_schedule_setting, 13)

    {execution, [], [am_scheduled], []} = get_task_computations(execution, :morning_update)
    assert execution

    Logger.info(
      "test: 1st computation scheduled for #{am_scheduled.scheduled_time} (#{DateTime.from_unix!(am_scheduled.scheduled_time)})"
    )

    assert am_scheduled.scheduled_time > Journey.Utilities.curent_unix_time_sec()
    assert rem(am_scheduled.scheduled_time, 60) == 13

    wait_for_computation(am_scheduled)

    # Make sure the scheduled computation completed, and a new computation was scheduled.
    {execution, [am_computed], [new_am_scheduled], []} = get_task_computations(execution, :morning_update)
    assert am_computed.id == am_scheduled.id

    assert rem(new_am_scheduled.scheduled_time, 60) == 13
    until_scheduled_run_seconds = new_am_scheduled.scheduled_time - Journey.Utilities.curent_unix_time_sec()

    Logger.info(
      "test: 1st computation completed, 2nd computation got scheduled for  #{new_am_scheduled.scheduled_time} (#{DateTime.from_unix!(new_am_scheduled.scheduled_time)}), in #{until_scheduled_run_seconds} seconds."
    )

    Logger.info(
      "test: attempting to reschedule the scheduled computation, by changing configuration and canceling the currently scheduled computation"
    )

    # Update scheduling configuration.
    execution =
      execution
      |> Journey.Execution.set_value(:morning_schedule_setting, 22)

    # Canceling the currently scheduled task (another computation should get scheduled, based on the new schedule configuration).
    {:ok, updated_computations, execution} =
      Journey.Execution.Scheduler2.cancel_scheduled_computations(execution, :morning_update)

    Logger.info("test: canceled scheduled computation: #{Enum.map_join(updated_computations, ", ", &str_summary/1)}")

    # Wait a bit to see if a new computation gets scheduled, at the new time.
    Logger.info("test: waiting for the cancellation to be picked up and processed by the sweeper")
    wait_for_the_sweeper()
    {execution, _am_computeds, [rescheduled], []} = get_task_computations(execution, :morning_update)
    assert rem(rescheduled.scheduled_time, 60) == 22

    wait_for_computation(rescheduled)

    # The newly scheduled computation should eventually execute.
    {_execution, all_computeds, [_scheduled], []} = get_task_computations(execution, :morning_update)
    assert rescheduled.id in Enum.map(all_computeds, fn c -> c.id end)

    # Make sure the computation executed close to its scheduled time.
    computed = Enum.find(all_computeds, fn c -> c.id == rescheduled.id end)

    assert_in_delta rescheduled.scheduled_time,
                    computed.start_time,
                    Journey.Application.sweeper_period_seconds() * 3
  end

  def wait_for_the_sweeper() do
    sweeper_wait_time = Journey.Application.sweeper_period_seconds() * 3
    Logger.info("test: giving sweeper #{sweeper_wait_time} seconds to wake up and do its thing")
    :timer.sleep(sweeper_wait_time * 1000)
  end

  def wait_for_computation(scheduled_computation) do
    until_scheduled_run_seconds = scheduled_computation.scheduled_time - Journey.Utilities.curent_unix_time_sec()
    Logger.info("test: waiting #{until_scheduled_run_seconds} seconds until scheduled run")
    :timer.sleep(until_scheduled_run_seconds * 1000)

    wait_for_the_sweeper()
    assert Journey.Utilities.curent_unix_time_sec() > scheduled_computation.scheduled_time
  end
end
