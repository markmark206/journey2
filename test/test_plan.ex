defmodule Journey.Test.UserJourney do
  require Logger
  import Journey.Utilities, only: [f_name: 0]

  def itinerary(slow \\ false, fail \\ true) do
    %Journey.Process{
      process_id: "#{__MODULE__}_slow_#{slow}_fail_#{fail}",
      steps: [
        %Journey.Process.Step{name: :user_id},
        %Journey.Process.Step{
          name: :morning_update,
          func: fn execution -> Journey.Test.UserJourney.send_morning_update(execution, slow, fail) end,
          blocked_by: [
            %Journey.Process.BlockedBy{step_name: :user_id, condition: :provided}
          ]
        },
        %Journey.Process.Step{
          name: :evening_check_in,
          func: fn execution -> Journey.Test.UserJourney.send_evening_check_in(execution, slow, fail) end,
          blocked_by: [
            %Journey.Process.BlockedBy{step_name: :user_id, condition: :provided}
          ]
        },
        %Journey.Process.Step{
          name: :user_lifetime_completed,
          func: fn execution -> Journey.Test.UserJourney.user_lifetime_completed(execution, slow, fail) end,
          blocked_by: [
            %Journey.Process.BlockedBy{step_name: :evening_check_in, condition: :provided},
            %Journey.Process.BlockedBy{step_name: :morning_update, condition: :provided}
          ]
        }
      ]
    }
  end

  def send_evening_check_in(execution, slow, _fail) do
    function_name = "[#{f_name()}][#{user_id(execution)}]"
    Logger.info("#{function_name}: starting")

    if slow do
      :timer.sleep(2000)
    end

    current_time_seconds = Journey.Utilities.curent_unix_time_sec()
    run_result = "#{execution.process_id}.#{f_name()} for user #{user_id(execution)}"

    Logger.info("#{function_name}: done.")

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

  def send_morning_update(execution, slow, _fail) do
    function_name = "[#{f_name()}][#{user_id(execution)}]"
    Logger.info("#{function_name}: starting")

    if slow do
      :timer.sleep(3000)
    end

    current_time_seconds = Journey.Utilities.curent_unix_time_sec()
    run_result = "#{execution.process_id}.#{f_name()} for user #{user_id(execution)}"

    Logger.info("#{function_name}: done.")

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

  def user_lifetime_completed(execution, slow, fail) do
    function_name = "[#{f_name()}][#{user_id(execution)}]"
    Logger.info("#{function_name}: starting. execution: #{inspect(execution, pretty: true)}")

    if slow do
      :timer.sleep(2000)
    end

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

    Logger.info("#{function_name}: computations so far: [#{computations_so_far}]")

    Logger.info("#{function_name}: using ")

    if fail do
      {_a, _b} = "testing failure"
    end

    run_result = [
      "#{execution.process_id}.#{f_name()} for user #{user_id(execution)}",
      computations_so_far
    ]

    Logger.info("#{function_name}: all done")
    {:ok, run_result}
  end
end
