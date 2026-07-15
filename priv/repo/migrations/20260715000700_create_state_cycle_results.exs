defmodule VNI.Repo.Migrations.CreateStateCycleResults do
  use Ecto.Migration

  def change do
    create table(:state_cycle_results) do
      add :state, :string, null: false
      add :cycle, :integer, null: false
      add :seats_dem, :integer, null: false, default: 0
      add :seats_rep, :integer, null: false, default: 0
      add :seats_other, :integer, null: false, default: 0
      add :pres_r_share, :float
      add :seats_source_url, :string, null: false
      add :pres_source_url, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:state_cycle_results, [:state, :cycle])
  end
end
