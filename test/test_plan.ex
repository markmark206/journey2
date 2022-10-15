defmodule Journey.Test.UserJourney do
  require Logger

  def itinerary() do
    %Journey.Process{
      process_id: "user journey",
      steps: [
        %Journey.Process.Step{name: :user_id},
        %Journey.Process.Step{
          name: :morning_update,
          func: &Journey.Test.UserJourney.send_morning_update/1,
          blocked_by: [
            %Journey.Process.BlockedBy{step_name: :user_id, condition: :provided}
          ]
        },
        %Journey.Process.Step{
          name: :evening_check_in,
          func: &Journey.Test.UserJourney.send_evening_check_in/1,
          blocked_by: [
            %Journey.Process.BlockedBy{step_name: :user_id, condition: :provided}
          ]
        },
        %Journey.Process.Step{
          name: :user_lifetime_completed,
          func: &Journey.Test.UserJourney.user_lifetime_completed/1,
          blocked_by: [
            %Journey.Process.BlockedBy{step_name: :evening_check_in, condition: :provided},
            %Journey.Process.BlockedBy{step_name: :evening_check_in, condition: :provided}
          ]
        }
      ]
    }
  end

  # @five_minutes 60 * 5
  # @three_minutes 60 * 3

  def send_evening_check_in(values) do
    function_name = "send_evening_check_in[#{values[:user_id].value}]"
    Logger.info("#{function_name}: starting")
    :timer.sleep(10000)

    current_time_seconds = Journey.Utilities.curent_unix_time_sec()
    run_result = "evening check in #{values[:user_id].value}#{current_time_seconds}"

    if rem(current_time_seconds, 100) == 0 do
      Logger.info("#{function_name}: done, forever.")
      # Don't run again, just record, the result.
      {:ok, run_result}
    else
      Logger.info("#{function_name}: done, let's do this again.")
      # Run again in five minutes.
      # This is not currently implemented, of course, just prototyping things a bit. (10/13/2022)
      # {:ok_run_again, %{next_run_in_seconds: five_minutes, result: run_result}}
      {:ok, run_result}
    end
  end

  def send_morning_update(values) do
    function_name = "send_morning_update[#{values[:user_id].value}]"
    Logger.info("#{function_name}: starting")

    :timer.sleep(15000)

    current_time_seconds = Journey.Utilities.curent_unix_time_sec()
    run_result = "evening check in #{values[:user_id].value}#{current_time_seconds}"

    if rem(current_time_seconds, 100) == 0 do
      Logger.info("#{function_name}: done, forever.")
      # Don't run again, just record, the result.
      {:ok, run_result}
    else
      Logger.info("#{function_name}: done, let's do this again.")
      # Run again in five minutes.
      # This is not currently implemented, of course, just prototyping things a bit. (10/13/2022)
      # {:ok_run_again, %{next_run_in_seconds: three_minutes, result: run_result}}
      {:ok, run_result}
    end
  end

  def user_lifetime_completed(values) do
    function_name = "user_lifetime_completed[#{values[:user_id].value}]"
    Logger.info("#{function_name}: starting")
    current_time_seconds = Journey.Utilities.curent_unix_time_sec()
    Logger.info("#{function_name}: all done")
    {:ok, current_time_seconds}
  end
end
