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
    field(:deadline, :integer)
    field(:result_code, Ecto.Enum, values: [nil, :computing, :computed, :failed, :expired, :scheduled], default: nil)
    field(:result_value, :map)
    field(:error_details, :string)
    field(:ex_revision, :integer, default: 0)
    timestamps()
  end
end
