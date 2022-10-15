defmodule Journey.Utilities do
  def curent_unix_time_sec() do
    System.os_time(:second)
  end

  @dictionary "1234567890qwertyuiopasdfghjklzxcvbnmQWERTYUIOPASDFGHJKLZXCVBNM"

  @spec object_id(String.t(), integer()) :: String.t()
  def object_id(prefix, length \\ 22) do
    prefix <> Nanoid.generate(length, @dictionary)
  end
end
