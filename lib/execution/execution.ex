defmodule Journey.Execution do
  defstruct [
    :id,
    :process_id,
    :computations
  ]

  def set_value(execution, _step, _value) do
    execution
  end

  def reload(execution) do
    execution
  end

  def get_unfilled_steps(_execution) do
    []
  end

  def get_summary(execution) do
    "execution summary. TODO: implement '#{execution.id}'"
  end
end
