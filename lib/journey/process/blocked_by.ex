defmodule Journey.Process.ValueCondition do
  defstruct [
    :condition,
    :value
  ]

  @type t :: %__MODULE__{
          condition: :provided | :equal,
          value: any()
        }
end

defmodule Journey.Process.BlockedBy do
  defstruct [
    :step_name,
    :condition
  ]

  @type t :: %__MODULE__{
          step_name: atom(),
          condition: Journey.Process.ValueCondition.t()
        }
end
