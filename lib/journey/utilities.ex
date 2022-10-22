defmodule Journey.Utilities do
  def curent_unix_time_sec() do
    System.os_time(:second)
  end

  @dictionary "1234567890qwertyuiopasdfghjklzxcvbnmQWERTYUIOPASDFGHJKLZXCVBNM"

  @spec object_id(String.t(), integer()) :: String.t()
  def object_id(prefix, length \\ 22) do
    prefix <> Nanoid.generate(length, @dictionary)
  end

  def epoch_to_timestamp(epoch_seconds, tz_name \\ "America/Los_Angeles") do
    timezone = Timex.Timezone.get(tz_name, Timex.now())

    epoch_seconds
    |> DateTime.from_unix!()
    |> Timex.Timezone.convert(timezone)
    |> Timex.format!("{YYYY}/{M}/{D} {h12}:{m}:{s}{am}")
  end

  def get_call_stack() do
    Process.info(self(), :current_stacktrace)
    |> elem(1)
    |> Enum.map(fn {module, func, arity, [file: file_name, line: linenum]} ->
      "#{module}.#{func}/#{arity} (#{file_name}:#{linenum}"
    end)
    |> then(fn [_ | [_ | rest]] -> rest end)
  end

  def function_name(f) do
    {_, module} = Function.info(f, :module)
    {_, name} = Function.info(f, :name)
    {_, arity} = Function.info(f, :arity)

    "#{module}.#{name}/#{arity}"
  end

  defp round_down_to_minute(epoch_seconds) do
    div(epoch_seconds, 60) * 60
  end

  def seconds_until_the_end_of_next_minute() do
    now = Journey.Utilities.curent_unix_time_sec()

    end_of_next_minute =
      now
      |> round_down_to_minute()
      # Next minute.
      |> Kernel.+(60)
      # last second of the next minute.
      |> Kernel.+(59)

    end_of_next_minute - now
  end

  defmacro f_name() do
    elem(__CALLER__.function, 0)
  end
end
