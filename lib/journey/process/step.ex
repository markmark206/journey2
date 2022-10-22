defmodule Journey.Process.Step do
  @derive Jason.Encoder
  @enforce_keys [:name]
  defstruct [
    :name,
    func: nil,
    func_next_execution_time_epoch_seconds: nil,
    expires_after_seconds: 60,
    blocked_by: []
    # TODO: add retry policy
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          func: (map() -> {:ok | :retriable | :error | :ok_run_again_at, any()}),
          func_next_execution_time_epoch_seconds: (map() -> integer()),
          blocked_by: list()
        }
end
