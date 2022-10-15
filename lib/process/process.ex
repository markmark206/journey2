defmodule Journey.Process do
  defstruct [
    :process_id,
    :steps
  ]

  @type t :: %__MODULE__{
          process_id: String.t(),
          steps: list()
        }

  def start(_itinerary) do
    %{id: "123"}
  end
end
