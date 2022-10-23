defmodule Journey.Test.Utilities do
  use ExUnit.Case
  require Logger

  import Journey.Utilities, only: [f_name: 0]

  test "test curent_unix_time_sec" do
    t1 = Journey.Utilities.curent_unix_time_sec()
    :timer.sleep(1000)
    t2 = Journey.Utilities.curent_unix_time_sec()
    assert t2 > t1
  end

  def test_function_public() do
    assert f_name() == :test_function_public
  end

  defp test_function_private() do
    assert f_name() == :test_function_private
  end

  test "f_name" do
    test_function_public()
    test_function_private()
    assert f_name() == :"test f_name"
  end

  def test_callstack() do
    assert Journey.Utilities.get_call_stack() |> IO.inspect()
  end

  test "callstack" do
    test_callstack()
  end
end
