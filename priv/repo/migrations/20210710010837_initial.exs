defmodule Journey.Repo.Migrations.Initial do
  use Ecto.Migration

  def change do
    create table(:executions, primary_key: false) do
      add(:id, :string, primary_key: true)
      add(:process_id, :string)
      add(:revision, :integer, default: 0)
      timestamps(type: :bigint)
    end

    create table(:computations, primary_key: false) do
      add(:id, :string, primary_key: true)
      add(:execution_id, :string)
      add(:name, :string)
      add(:scheduled_time, :bigint)
      add(:start_time, :bigint)
      add(:end_time, :bigint)
      add(:deadline, :bigint)
      add(:result_code, :string)
      add(:result_value, :map)
      add(:error_details, :string)
      add(:ex_revision, :integer, default: 0)
      timestamps(type: :bigint)
    end

    create(index(:computations, [:execution_id, :name]))
    create(index(:computations, [:start_time]))
    create(index(:computations, [:end_time]))
    create(index(:computations, [:deadline]))
    create(index(:computations, [:scheduled_time]))
  end
end
