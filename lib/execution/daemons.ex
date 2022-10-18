defmodule Journey.Execution.Daemons do
  require Logger
  import Journey.Utilities, only: [f_name: 0]

  def sweep_and_revisit_expired_computations() do
    # Sweep expired computations, and kick off processing for corresponding executions.
    Logger.info("#{f_name()}: enter")

    # TODO: what do we want to do with abandoned scheduled tasks? (run them now, or wait until next scheduled time?)
    Journey.Execution.Store.mark_abandoned_computations_as_expired()
    |> Enum.map(fn expired_computation ->
      Logger.info("#{f_name()}: processing expired computation, #{inspect(expired_computation, pretty: true)}")
      expired_computation
    end)
    |> Enum.map(fn expired_computation -> expired_computation.execution_id end)
    |> Enum.uniq()
    # Revisit the execution, those abandoned / expired computations might still need to be computed.
    |> Enum.each(&Journey.Execution.kick_off_or_schedule_unblocked_steps_if_any/1)

    Logger.info("#{f_name()}: exit")
  end

  def delay_and_sweep(min_delay_in_seconds) do
    # Every once in a while (between min_delay_seconds and 2 * min_delay_seconds),
    # detect and "sweep" abandoned tasks.

    # TODO: move background sweepers into a separate module.

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
end
