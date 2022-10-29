defmodule Journey.Test.Plans.ScheduledRecurring do
  require Logger
  import Journey.Utilities, only: [f_name: 0]

  def itinerary() do
    %Journey.Process{
      process_id: "#{__MODULE__}",
      steps: [
        %Journey.Process.Step{name: :user_id},
        %Journey.Process.Step{name: :morning_schedule_setting},
        %Journey.Process.Step{name: :evening_schedule_setting},
        %Journey.Process.Step{
          name: :morning_update,
          func: &Journey.Test.Plans.ScheduledRecurring.send_morning_update/2,
          func_next_execution_time_epoch_seconds: &Journey.Test.Plans.ScheduledRecurring.tomorrow_morning/1,
          blocked_by: [
            %Journey.Process.BlockedBy{step_name: :user_id, condition: :provided},
            %Journey.Process.BlockedBy{step_name: :morning_schedule_setting, condition: :provided}
          ]
        },
        %Journey.Process.Step{
          name: :evening_check_in,
          func: &Journey.Test.Plans.ScheduledRecurring.send_evening_check_in/2,
          func_next_execution_time_epoch_seconds: &Journey.Test.Plans.ScheduledRecurring.tomorrow_evening/1,
          blocked_by: [
            %Journey.Process.BlockedBy{step_name: :user_id, condition: :provided},
            %Journey.Process.BlockedBy{step_name: :evening_schedule_setting, condition: :provided}
          ]
        }
      ]
    }
  end

  defp round_down_to_minute(epoch_seconds) do
    div(epoch_seconds, 60) * 60
  end

  @spec next_minute :: integer
  defp next_minute() do
    Journey.Utilities.curent_unix_time_sec()
    |> round_down_to_minute()
    # Next minute.
    |> Kernel.+(60)
  end

  @spec tomorrow_morning(map()) :: integer
  def tomorrow_morning(execution) do
    configured_seconds = Journey.Execution.Queries.get_computation_value(execution, :morning_schedule_setting)
    Logger.info("tomorrow_morning: configured offset: #{configured_seconds}")

    next_minute()
    # this many seconds after the minute.
    |> Kernel.+(configured_seconds)
  end

  @spec tomorrow_evening(map()) :: integer
  def tomorrow_evening(execution) do
    configured_seconds = Journey.Execution.Queries.get_computation_value(execution, :evening_schedule_setting)

    next_minute()
    # this many seconds after the minute.
    |> Kernel.+(configured_seconds)
  end

  def send_evening_check_in(execution, computation_id) do
    prefix = "#{f_name()}[#{execution.id}][#{computation_id}][#{user_id(execution)}]"
    Logger.info("#{prefix}: starting")

    run_result = "#{__MODULE__}.#{f_name()} for user #{user_id(execution)}"
    Logger.info("#{prefix}: done.")

    {:ok, run_result}
  end

  def send_morning_update(execution, computation_id) do
    prefix = "#{f_name()}[#{execution.id}][#{computation_id}][#{user_id(execution)}]"
    Logger.debug("#{prefix}: starting")

    run_result = "#{__MODULE__}.#{f_name()} for user #{user_id(execution)}"

    Logger.debug("#{prefix}: done.")

    {:ok, run_result}
  end

  defp user_id(execution) do
    Journey.Execution.Queries.get_computation_value(execution, :user_id)
  end
end
