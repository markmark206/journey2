defmodule Journey.Schema.Base do
  @moduledoc false
  defmacro __using__(_) do
    quote do
      use Ecto.Schema

      @primary_key {:id, :string,
                    autogenerate: {Journey.Utilities.CryptoRandom, :object_id, [""]}}

      @timestamps_opts [type: :integer, autogenerate: {System, :os_time, [:second]}]

      @foreign_key_type :string
    end
  end
end

defmodule Journey.Schema.Execution do
  @moduledoc false
  use Journey.Schema.Base

  @primary_key {:id, :string, autogenerate: {Journey.Utilities, :object_id, ["EXEC"]}}
  schema "executions" do
    timestamps()
  end
end

defmodule Journey.Schema.Computation do
  @moduledoc false
  use Journey.Schema.Base

  @primary_key {:id, :string, autogenerate: {Journey.Utilities, :object_id, ["COMP"]}}
  schema "computations" do
    field(:execution_id, :string)
    field(:name, :string)
    field(:scheduled_time, :integer)
    field(:start_time, :integer)
    field(:end_time, :integer)
    field(:revision, :integer)
    field(:result_code, Ecto.Enum, values: [nil, :computed, :failed], default: nil)
    field(:result_value, :map)
    timestamps()
  end
end
