defmodule Journey.Utilities do
  def curent_unix_time_sec() do
    System.os_time(:second)
  end

  @dictionary "1234567890qwertyuiopasdfghjklzxcvbnmQWERTYUIOPASDFGHJKLZXCVBNM"

  @spec object_id(String.t(), integer()) :: String.t()
  def object_id(prefix, length \\ 22) do
    prefix <> Nanoid.generate(length, @dictionary)
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
    [module: module, name: name, arity: arity, env: _, type: _] = Function.info(f)
    "#{module}.#{name}/#{arity}"
  end

  defmacro f_name() do
    elem(__CALLER__.function, 0)
  end
end
