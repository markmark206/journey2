defmodule Journey.Test.UserJourneyScheduledRecurring do
  require Logger
  import Journey.Utilities, only: [f_name: 0]

  @abandoned_task_expires_after_seconds 10

  def itinerary() do
    %Journey.Process{
      process_id: "#{__MODULE__}",
      steps: [
        %Journey.Process.Step{name: :user_id},
        %Journey.Process.Step{
          name: :morning_update,
          func: &Journey.Test.UserJourneyScheduledRecurring.send_morning_update/1,
          func_next_execution_time_epoch_seconds: &Journey.Test.UserJourneyScheduledRecurring.tomorrow_morning/1,
          blocked_by: [
            %Journey.Process.BlockedBy{step_name: :user_id, condition: :provided}
          ]
        },
        %Journey.Process.Step{
          name: :evening_check_in,
          func: &Journey.Test.UserJourneyScheduledRecurring.send_evening_check_in/1,
          func_next_execution_time_epoch_seconds: &Journey.Test.UserJourneyScheduledRecurring.tomorrow_evening/1,
          blocked_by: [
            %Journey.Process.BlockedBy{step_name: :user_id, condition: :provided}
          ]
        }
        # %Journey.Process.Step{
        #   name: :user_lifetime_completed,
        #   func: &Journey.Test.UserJourneyScheduledRecurring.user_lifetime_completed/1,
        #   expires_after_seconds: @abandoned_task_expires_after_seconds,
        #   blocked_by: [
        #     %Journey.Process.BlockedBy{step_name: :evening_check_in, condition: :provided},
        #     %Journey.Process.BlockedBy{step_name: :morning_update, condition: :provided}
        #   ]
        # }
      ]
    }
  end

  defp round_down_to_minute(epoch_seconds) do
    div(epoch_seconds, 60) * 60
  end

  #  defp round_down_to_hour(epoch_seconds) do
  #    div(epoch_seconds, 60 * 60) * 60 * 60
  #  end

  @spec tomorrow_morning(map()) :: integer
  def tomorrow_morning(_execution) do
    # 10 seconds after the next minute.
    Journey.Utilities.curent_unix_time_sec()
    |> round_down_to_minute()
    # Next minute.
    |> Kernel.+(60)
    # 10 seconds after the minute.
    |> Kernel.+(10)
  end

  @spec tomorrow_evening(map()) :: integer
  def tomorrow_evening(_execution) do
    # 30 seconds after the next minute.
    Journey.Utilities.curent_unix_time_sec()
    |> round_down_to_minute()
    # Next minute.
    |> Kernel.+(60)
    # 30 seconds after the minute.
    |> Kernel.+(30)
  end

  def send_evening_check_in(execution) do
    function_name = "#{f_name()}[#{user_id(execution)}]"
    Logger.debug("#{function_name}: starting")

    current_time_seconds = Journey.Utilities.curent_unix_time_sec()
    run_result = "#{__MODULE__}.#{f_name()} for user #{user_id(execution)}"
    Logger.debug("#{function_name}: done.")

    if rem(current_time_seconds, 100) == 0 do
      # Logger.info("#{function_name}: done, forever.")
      # Don't run again, just record, the result.
      {:ok, run_result}
    else
      # Logger.info("#{function_name}: done, let's do this again.")
      # Run again in five minutes.
      # TODO: implement
      # This is not currently implemented, of course, just prototyping things a bit. (10/13/2022)
      # {:ok_run_again, %{next_run_in_seconds: five_minutes, result: run_result}}
      {:ok, run_result}
    end
  end

  def send_morning_update(execution) do
    function_name = "#{f_name()}[#{user_id(execution)}]"
    Logger.debug("#{function_name}: starting")

    current_time_seconds = Journey.Utilities.curent_unix_time_sec()
    run_result = "#{__MODULE__}.#{f_name()} for user #{user_id(execution)}"

    Logger.debug("#{function_name}: done.")

    if rem(current_time_seconds, 100) == 0 do
      # Logger.info("#{function_name}: done, forever.")
      # Don't run again, just record, the result.
      {:ok, run_result}
    else
      # Logger.info("#{function_name}: done, let's do this again.")
      # Run again in five minutes.
      # TODO: implement
      # This is not currently implemented, of course, just prototyping things a bit. (10/13/2022)
      # {:ok_run_again, %{next_run_in_seconds: three_minutes, result: run_result}}
      {:ok, run_result}
    end
  end

  defp user_id(execution) do
    Journey.Execution.Queries.get_computation_value(execution, :user_id)
  end

  def user_lifetime_completed(execution) do
    function_name = "#{f_name()}[#{user_id(execution)}]"
    Logger.debug("#{function_name}: starting. execution: #{inspect(execution, pretty: true)}")

    # All of the upstream tasks must have been computed before this task starts computing.
    :computed = Journey.Execution.Queries.get_computation_status(execution, :user_id)
    :computed = Journey.Execution.Queries.get_computation_status(execution, :evening_check_in)
    :computed = Journey.Execution.Queries.get_computation_status(execution, :morning_update)

    computations_so_far =
      Enum.join(
        [
          Journey.Execution.Queries.get_computation_value(execution, :user_id),
          Journey.Execution.Queries.get_computation_value(execution, :morning_update),
          Journey.Execution.Queries.get_computation_value(execution, :evening_check_in)
        ],
        ", "
      )

    Logger.debug("#{function_name}: computations so far: [#{computations_so_far}]")

    Logger.debug("#{function_name}: using ")

    # TODO: receive task name as a function argument.
    # my_first_execution =
    # nil == Enum.find(execution.computations, fn computation -> computation.name == :user_lifetime_completed end)

    #    if my_first_execution do
    #      # Sleep long enough for the task to be considered abandoned.
    #      sleep_time_ms = (2 * @abandoned_task_expires_after_seconds + 5) * 1000
    #      :timer.sleep(sleep_time_ms)
    #    else
    #      # Just a quick nap, not long enough to be considered abandoned.
    :timer.sleep(1000 * floor(@abandoned_task_expires_after_seconds / 4))
    #    end

    run_result = [
      "user lifetime completed for user #{user_id(execution)}",
      computations_so_far
    ]

    Logger.info("#{function_name}: all done")
    {:ok, run_result}
  end
end
