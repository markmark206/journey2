defmodule Journey.Execution.Daemons do
  require Logger
  import Journey.Utilities, only: [f_name: 0]

  @spec collect_abandoned_computations :: list(String.t())
  defp collect_abandoned_computations() do
    # TODO: what do we want to do with abandoned scheduled tasks? (run them now, or wait until next scheduled time?)
    now = Journey.Utilities.curent_unix_time_sec()

    now
    |> Journey.Execution.Store.mark_abandoned_computations_as_expired(Journey.ProcessCatalog.get_registered_processes())
    |> Enum.map(fn expired_computation ->
      prefix = "#{f_name()}[#{expired_computation.execution_id}][#{expired_computation.id}]"

      Logger.warn(
        "#{prefix}: processing expired computation. status: #{expired_computation.result_code}, deadline: #{expired_computation.deadline} (now: #{now}, passed by #{now - expired_computation.deadline} seconds)"
      )

      expired_computation
    end)
    |> Enum.map(fn expired_computation -> expired_computation.execution_id end)
  end

  @spec collect_past_due_scheduled_computations :: list(String.t())
  defp collect_past_due_scheduled_computations() do
    past_due_deadline_seconds = 3

    Journey.Execution.Store.find_scheduled_computations_that_are_past_due(
      past_due_deadline_seconds,
      Journey.ProcessCatalog.get_registered_processes()
    )
    |> case do
      [] ->
        []

      past_due_computations ->
        Logger.info(
          "sweeper detected #{Enum.count(past_due_computations)} executions with past due computations. #{Enum.join(past_due_computations, ", ")}"
        )

        past_due_computations
    end
  end

  def find_canceled_computations() do
    Journey.Execution.Store.find_canceled_computations(Journey.ProcessCatalog.get_registered_processes())
    |> case do
      [] ->
        []

      canceled_computations ->
        Logger.info(
          "sweeper detected #{Enum.count(canceled_computations)} unscheduled schedule computations, in #{Enum.join(canceled_computations, ", ")}"
        )

        canceled_computations
    end
  end

  defp collect_unscheduled_scheduled_executions() do
    Journey.ProcessCatalog.get_registered_processes()
    |> Journey.Execution.Store.find_executions_with_unscheduled_schedulable_tasks()
    |> case do
      [] ->
        []

      unscheduled_schedule_tasks ->
        Logger.info(
          "sweeper detected #{Enum.count(unscheduled_schedule_tasks)} unscheduled schedule computations, in #{Enum.join(unscheduled_schedule_tasks, ", ")}"
        )

        unscheduled_schedule_tasks
    end
  end

  @spec sweep_and_revisit_expired_computations :: :ok
  defp sweep_and_revisit_expired_computations() do
    # Sweep expired computations, and kick off processing for corresponding executions.
    Logger.debug("#{f_name()}: enter")

    Journey.Execution.Store.find_scheduled_computations_same_scheduled_time()
    |> case do
      [] ->
        :ok

      duplicate_schedules ->
        # some of the computations were scheduled for the same time. Log them, and proceed.
        Logger.warning(
          "#{f_name()}: detected #{Enum.count(duplicate_schedules)} instance(s) of duplicate schedules:\n: #{inspect(duplicate_schedules, pretty: true)}"
        )

        :ok
    end

    (collect_abandoned_computations() ++
       collect_past_due_scheduled_computations() ++
       collect_unscheduled_scheduled_executions() ++ find_canceled_computations())
    |> Enum.uniq()
    # Revisit the execution, those abandoned / expired computations might still need to be computed.
    # |> Enum.each(&Journey.Execution.Scheduler.kick_off_or_schedule_unblocked_steps_if_any/1)
    |> Enum.each(&Journey.Execution.Scheduler2.advance/1)

    Logger.debug("#{f_name()}: exit")
  end

  def delay_and_sweep_task(min_delay_in_seconds) do
    Logger.info("delay_and_sweep_task: starting... base delay: #{min_delay_in_seconds} seconds")
    delay_and_sweep(min_delay_in_seconds)
  end

  @spec delay_and_sweep(number) :: no_return
  def delay_and_sweep(min_delay_in_seconds) do
    # Every once in a while (between min_delay_seconds and 2 * min_delay_seconds),
    # detect and "sweep" abandoned tasks.

    registered_processes = Journey.ProcessCatalog.get_registered_processes() |> Enum.join(", ")

    Logger.debug(
      "delay_and_sweep: starting run (base delay: #{min_delay_in_seconds} seconds). registered processes: '#{registered_processes}'"
    )

    to_random_ms = fn base_sec ->
      ((base_sec + base_sec * :rand.uniform()) * 1000) |> round()
    end

    min_delay_in_seconds
    |> then(to_random_ms)
    |> :timer.sleep()

    sweep_and_revisit_expired_computations()
    Logger.debug("delay_and_sweep: ending run")
    delay_and_sweep(min_delay_in_seconds)
  end

  @spec start(number) :: {:ok, pid}
  def start(min_delay_seconds) do
    # TODO: kick this off as a supervised task.
    {:ok, _pid} =
      Task.start(fn ->
        Journey.Execution.Daemons.delay_and_sweep_task(min_delay_seconds)
      end)
      |> tap(fn {:ok, pid} ->
        Logger.info("background sweeping process started. #{inspect(pid)}")
      end)
  end

  # def shutdown(pid) do
  #   Task.shutdown(pid)
  # end
end
