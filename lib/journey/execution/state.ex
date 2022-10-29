defmodule Journey.Execution.State do
  @type execution_state ::
          nil
          | :computing
          | :computed
          | :failed
          | :expired
          | :scheduled
          | :canceled
          | :rescheduled

  @states [
    nil,
    :computing,
    :computed,
    :failed,
    :expired,
    :scheduled,
    :canceled,
    :rescheduled
  ]

  @spec values :: [execution_state()]
  def values() do
    @states
  end
end
