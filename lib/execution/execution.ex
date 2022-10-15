defmodule Journey.Execution do
  # defstruct [
  #  :id,
  #  :process_id,
  #  :computations
  # ]

  def new(process_id) do
    Journey.Execution.Store.create_initial_record(process_id)
  end

  def set_value(execution, step, value) do
    Journey.Execution.Store.set_value(execution, step, value)
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
