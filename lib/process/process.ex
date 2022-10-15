defmodule Journey.Process do
  defstruct [
    :process_id,
    :steps
  ]

  @type t :: %__MODULE__{
          process_id: String.t(),
          steps: list()
        }

  defp prepend_with_start_time(itinerary) do
    %{itinerary | steps: [%Journey.Process.Step{name: :started_at}] ++ itinerary.steps}
  end

  def start(itinerary) do
    itinerary =
      itinerary
      |> prepend_with_start_time()
      |> Journey.ProcessCatalog.register()

    _execution =
      itinerary.process_id
      |> Journey.Execution.new()
      |> Journey.Execution.set_value(:started_at, Journey.Utilities.curent_unix_time_sec())
      |> dbg()
  end
end
