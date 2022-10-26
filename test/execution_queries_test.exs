defmodule Journey.Test.Execution.Queries do
  use Journey.RepoCase

  setup do
    {:ok, %{test_id: Journey.Utilities.object_id("tid")}}
  end

  test "find execution by value", %{test_id: test_id} do
    user_id = "user_test_reference_id_#{test_id}"

    execution =
      Journey.Test.UserJourney.itinerary()
      |> Journey.Process.register_itinerary()
      |> Journey.Process.start()
      |> Journey.Execution.set_value(:user_id, user_id)

    [execution_loaded] = Journey.Execution.Queries.find_by_value(:user_id, user_id)

    assert execution_loaded
    assert execution_loaded.id == execution.id
    assert Journey.Execution.Queries.get_computation_value(execution_loaded, :user_id) == user_id
  end
end
