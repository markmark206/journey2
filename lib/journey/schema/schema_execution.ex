defmodule Journey.Schema.Execution do
  @moduledoc false
  use Journey.Schema.Base

  @primary_key {:id, :string, autogenerate: {Journey.Utilities, :object_id, ["EXEC"]}}
  schema "executions" do
    field(:process_id, :string)
    has_many(:computations, Journey.Schema.Computation, preload_order: [asc: :ex_revision])
    field(:revision, :integer, default: 0)
    timestamps()
  end
end
