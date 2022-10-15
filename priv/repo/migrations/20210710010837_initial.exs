defmodule Journey.Repo.Migrations.Initial do
  use Ecto.Migration

  def change do
    create table(:executions, primary_key: false) do
      add(:id, :string, primary_key: true)
      add(:process_id, :string)
      timestamps(type: :bigint)
    end

    create table(:computations, primary_key: false) do
      add(:id, :string, primary_key: true)
      add(:execution_id, :string)
      add(:name, :string)
      add(:scheduled_time, :integer)
      add(:start_time, :bigint)
      add(:end_time, :bigint)
      add(:result_code, :string)
      add(:result_value, :map)
      timestamps(type: :bigint)
    end

    create(index(:computations, [:execution_id, :name]))
    create(index(:computations, [:start_time]))
    create(index(:computations, [:end_time]))
    create(index(:computations, [:scheduled_time]))
  end
end
