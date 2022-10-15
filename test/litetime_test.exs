defmodule Journey.Test.Lifetime do
  use ExUnit.Case

  require WaitForIt

  test "execute a basic process" do
    # Start process execution.
    execution =
      Journey.Test.UserJourney.itinerary()
      |> Journey.Process.start()

    assert execution

    execution = Journey.Execution.set_value(execution, :user_id, "user1")
    assert execution

    case WaitForIt.wait(
           Journey.Execution.reload(execution.id)
           |> Journey.Execution.get_unfilled_steps()
           |> Enum.count() == 0,
           timeout: 5_000,
           frequency: 1000
         ) do
      {:ok, _} ->
        true

      {:timeout, _timeout} ->
        {:ok, execution} = Journey.Execution.reload(execution)
        execution |> Journey.Execution.get_summary() |> IO.puts()
        assert false, "horoscope step never computed"
    end
  end
end
