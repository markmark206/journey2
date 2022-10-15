defmodule Journey.Test.Utilities do
  use ExUnit.Case

  test "test curent_unix_time_sec" do
    t1 = Journey.Utilities.curent_unix_time_sec()
    :timer.sleep(1000)
    t2 = Journey.Utilities.curent_unix_time_sec()
    assert t2 > t1
  end
end
