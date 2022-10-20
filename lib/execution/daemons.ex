defmodule Journey.Execution.Daemons do
  require Logger
  import Journey.Utilities, only: [f_name: 0]

  @spec collect_abandoned_computations :: list(String.t())
  defp collect_abandoned_computations() do
    # TODO: what do we want to do with abandoned scheduled tasks? (run them now, or wait until next scheduled time?)
    Journey.Execution.Store.mark_abandoned_computations_as_expired()
    |> Enum.map(fn expired_computation ->
      Logger.info("#{f_name()}: processing expired computation, #{inspect(expired_computation, pretty: true)}")
      expired_computation
    end)
    # TODO: have mark_abandoned_computations_as_expired return execution ids
    |> Enum.map(fn expired_computation -> expired_computation.execution_id end)
  end

  @spec collect_past_due_scheduled_computations :: list(String.t())
  defp collect_past_due_scheduled_computations() do
    past_due_deadline_seconds = 3

    Journey.Execution.Store.find_scheduled_computations_that_are_past_due(past_due_deadline_seconds)
  end

  defp collect_unscheduled_scheduled_executions() do
    Journey.Execution.Store.find_executions_with_unscheduled_schedulable_tasks()
  end

  @spec sweep_and_revisit_expired_computations :: :ok
  defp sweep_and_revisit_expired_computations() do
    # Sweep expired computations, and kick off processing for corresponding executions.
    Logger.info("#{f_name()}: enter")

    # Journey.Execution.Store.find_scheduled_computations_same_scheduled_time() do
    case [] do
      [] ->
        nil

      duplicate_schedules ->
        # some of the computations were scheduled for the same time. Log them, and proceed.
        Logger.error(
          "#{f_name()}: detected #{Enum.count(duplicate_schedules)} instance(s) of duplicate schedules:\n: #{inspect(duplicate_schedules, pretty: true)}"
        )
    end

    (collect_abandoned_computations() ++
       collect_past_due_scheduled_computations() ++ collect_unscheduled_scheduled_executions())
    |> Enum.uniq()
    # Revisit the execution, those abandoned / expired computations might still need to be computed.
    |> Enum.each(&Journey.Execution.Scheduler.kick_off_or_schedule_unblocked_steps_if_any/1)

    Logger.info("#{f_name()}: exit")
  end

  @spec delay_and_sweep(number) :: no_return
  def delay_and_sweep(min_delay_in_seconds) do
    # Every once in a while (between min_delay_seconds and 2 * min_delay_seconds),
    # detect and "sweep" abandoned tasks.

    Logger.info("delay_and_sweep: starting run (base delay: #{min_delay_in_seconds} seconds)")

    to_random_ms = fn base_sec ->
      ((base_sec + base_sec * :rand.uniform()) * 1000) |> round()
    end

    min_delay_in_seconds
    |> then(to_random_ms)
    |> :timer.sleep()

    sweep_and_revisit_expired_computations()
    Logger.info("delay_and_sweep: ending run")
    delay_and_sweep(min_delay_in_seconds)
  end

  @spec start(number) :: {:ok, pid}
  def start(min_delay_seconds) do
    # TODO: kick this off as a supervised task.
    {:ok, _pid} =
      Task.start(fn ->
        Journey.Execution.Daemons.delay_and_sweep(min_delay_seconds)
      end)
  end
end
