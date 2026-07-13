defmodule VNI.Repo.Migrations.CreateDistrictProfiles do
  use Ecto.Migration

  def change do
    create table(:district_profiles) do
      add :district_id, references(:districts, on_delete: :delete_all), null: false
      add :incumbent_name, :string
      add :incumbent_party, :string
      add :incumbent_since, :integer
      add :last_margin_pct, :float
      add :partisan_lean, :float
      add :bioguide_id, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:district_profiles, [:district_id])
    create index(:district_profiles, [:bioguide_id])
  end
end
