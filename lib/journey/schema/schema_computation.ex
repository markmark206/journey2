defmodule Journey.Schema.Computation do
  @moduledoc false
  use Journey.Schema.Base

  @primary_key {:id, :string, autogenerate: {Journey.Utilities, :object_id, ["COMP"]}}
  schema "computations" do
    belongs_to(:execution, Journey.Schema.Execution)
    # field(:execution_id, :string)
    field(:name, :string)
    field(:scheduled_time, :integer)
    field(:start_time, :integer)
    field(:end_time, :integer)
    field(:result_code, Ecto.Enum, values: [nil, :computed, :failed], default: nil)
    field(:result_value, :map)
    timestamps()
  end
end
