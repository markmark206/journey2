defmodule Journey.Test.Basic do
  use Journey.RepoCase

  import Journey.Test.Helpers

  require Logger

  setup do
    {:ok, %{test_id: Journey.Utilities.object_id("tid")}}
  end

  def testing_basic_process(test_id, slow, fail) do
    # Ecto.Adapters.SQL.Sandbox.unboxed_run(Journey.Repo, fn ->

    itinerary = Journey.Test.Plans.Basic.itinerary(slow, fail)
    Journey.Process.register_itinerary(itinerary)

    user_id = "user_basic_#{slow}_#{fail}_#{test_id}"

    execution =
      itinerary
      |> Journey.Process.start()

    assert execution

    if slow do
      :timer.sleep(1000)
    end

    # Set the value for the 1st step.
    execution =
      execution
      |> Journey.Execution.set_value(:user_id, user_id)

    assert execution

    # The remaining steps should promptly compute.
    wait_for_result_to_compute(execution, :morning_update, check_wait(slow), check_frequency(slow))
    wait_for_result_to_compute(execution, :evening_check_in, check_wait(slow), check_frequency(slow))

    wait_for_result_to_compute(
      execution,
      :user_lifetime_completed,
      check_wait(slow),
      check_frequency(slow),
      if(fail, do: :failed, else: :computed)
    )

    wait_for_all_steps_to_be_completed(execution, check_wait(slow), check_frequency(slow))

    execution =
      execution
      |> Journey.Execution.reload()

    one_year_ish = 60 * 60 * 24 * 365
    now = Journey.Utilities.curent_unix_time_sec()
    assert Journey.Execution.Queries.get_computation_status(execution, :started_at) == :computed
    assert Journey.Execution.Queries.get_computation(execution, :started_at).error_details == nil
    assert Journey.Execution.Queries.get_computation_value(execution, :started_at) <= now
    assert Journey.Execution.Queries.get_computation_value(execution, :started_at) >= now - one_year_ish

    assert Journey.Execution.Queries.get_computation_status(execution, :user_id) == :computed
    assert Journey.Execution.Queries.get_computation(execution, :user_id).error_details == nil
    assert Journey.Execution.Queries.get_computation_value(execution, :user_id) == user_id

    assert Journey.Execution.Queries.get_computation_status(execution, :morning_update) == :computed
    assert Journey.Execution.Queries.get_computation(execution, :morning_update).error_details == nil

    expected_morning_update_result =
      "Elixir.Journey.Test.Plans.Basic_slow_#{slow}_fail_#{fail}.send_morning_update for user #{user_id}"

    assert Journey.Execution.Queries.get_computation_value(execution, :morning_update) ==
             expected_morning_update_result

    assert Journey.Execution.Queries.get_computation_status(execution, :evening_check_in) == :computed
    assert Journey.Execution.Queries.get_computation(execution, :evening_check_in).error_details == nil

    expected_evening_checkin_result =
      "Elixir.Journey.Test.Plans.Basic_slow_#{slow}_fail_#{fail}.send_evening_check_in for user #{user_id}"

    assert Journey.Execution.Queries.get_computation_value(execution, :evening_check_in) ==
             expected_evening_checkin_result

    if fail do
      assert Journey.Execution.Queries.get_computation_status(execution, :user_lifetime_completed) == :failed
      assert Journey.Execution.Queries.get_computation(execution, :user_lifetime_completed).error_details != nil
      assert Journey.Execution.Queries.get_computation_value(execution, :user_lifetime_completed) == nil
    else
      assert Journey.Execution.Queries.get_computation_status(execution, :user_lifetime_completed) == :computed
      assert Journey.Execution.Queries.get_computation(execution, :user_lifetime_completed).error_details == nil

      assert Journey.Execution.Queries.get_computation_value(execution, :user_lifetime_completed) == [
               "Elixir.Journey.Test.Plans.Basic_slow_#{slow}_fail_#{fail}.user_lifetime_completed for user #{user_id}",
               Enum.join(["#{user_id}", expected_morning_update_result, expected_evening_checkin_result], ", ")
             ]
    end

    execution =
      execution
      |> Journey.Execution.reload()

    execution_summary = Journey.Execution.get_summary(execution)
    Logger.info("test execution summary:\n#{execution_summary}")

    # end)
  end

  @tag timeout: 600_000
  test "execute a basic process (slow, force failure)", %{test_id: test_id} do
    # Ecto.Adapters.SQL.Sandbox.unboxed_run(Journey.Repo, fn ->
    testing_basic_process(test_id, true, true)
    # end)
  end

  @tag timeout: 600_000
  @tag fast: true
  test "execute a basic process (fast, force failure)", %{test_id: test_id} do
    # Ecto.Adapters.SQL.Sandbox.unboxed_run(Journey.Repo, fn ->
    testing_basic_process(test_id, false, true)
    # end)
  end

  @tag timeout: 600_000
  test "execute a basic process (slow, success)", %{test_id: test_id} do
    # Ecto.Adapters.SQL.Sandbox.unboxed_run(Journey.Repo, fn ->
    testing_basic_process(test_id, true, false)
    # end)
  end

  @tag timeout: 600_000
  @tag fast: true
  test "execute a basic process (fast, success)", %{test_id: test_id} do
    # Ecto.Adapters.SQL.Sandbox.unboxed_run(Journey.Repo, fn ->
    testing_basic_process(test_id, false, false)
    # end)
  end

  defp check_frequency(slow) do
    if slow, do: 2_000, else: 100
  end

  defp check_wait(slow) do
    if slow, do: 10_000, else: 2000
  end
end
