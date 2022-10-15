defmodule Journey.Utilities do
  def curent_unix_time_sec() do
    System.os_time(:second)
  end
end
