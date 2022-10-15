defmodule Journey.Process.Step do
  @derive Jason.Encoder
  @enforce_keys [:name]
  defstruct [
    :name,
    func: nil,
    blocked_by: []
    # TODO: add retry policy
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          func: (map() -> {:ok | :retriable | :error | :ok_run_again_at, any()}),
          blocked_by: list()
        }
end
