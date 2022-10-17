defmodule Journey.Execution.Queries do
  def get_computation(execution, computation_name, most_recent \\ true) do
    # Get the most or least recent computation for the given task name.
    execution
    |> get_computations(computation_name)
    |> Enum.sort(fn c1, c2 ->
      if most_recent do
        c1.ex_revision > c2.ex_revision
      else
        c1.ex_revision < c2.ex_revision
      end
    end)
    |> Enum.take(1)
    |> case do
      [] -> nil
      [head | _] -> head
    end
  end

  def get_computations(execution, computation_name) do
    # Get all computations for the given task name.

    # TODO: replace this biz with a dictionary lookup.
    # TODO: raise if the name is not valid.
    execution.computations
    |> Enum.filter(fn c -> c.name == computation_name end)
  end

  def get_computation_status(execution, computation_name, most_recent \\ true) do
    execution
    |> get_computation(computation_name, most_recent)
    |> case do
      nil -> nil
      computation -> computation.result_code
    end
  end

  def get_computation_value(execution, computation_name, most_recent \\ true) do
    execution
    |> get_computation(computation_name, most_recent)
    |> case do
      nil -> nil
      computation -> computation.result_value
    end
  end
end
