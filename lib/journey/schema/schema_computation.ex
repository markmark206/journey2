defmodule Journey.Schema.Computation do
  @moduledoc false
  use Journey.Schema.Base
  import Journey.Execution.State, only: [values: 0]

  @primary_key {:id, :string, autogenerate: {Journey.Utilities, :object_id, ["COMP"]}}
  schema "computations" do
    belongs_to(:execution, Journey.Schema.Execution)
    # field(:execution_id, :string)
    field(:name, :string)
    field(:scheduled_time, :integer)
    field(:start_time, :integer)
    field(:end_time, :integer)
    field(:deadline, :integer)
    field(:result_code, Ecto.Enum, values: values(), default: nil)
    field(:result_value, :map)
    field(:error_details, :string)
    field(:ex_revision, :integer, default: 0)
    timestamps()
  end

  def str_summary(computation) do
    "[#{computation.execution_id}][#{computation.name}][#{computation.id}][#{computation.result_code}][rev #{computation.ex_revision}]"
  end
end
