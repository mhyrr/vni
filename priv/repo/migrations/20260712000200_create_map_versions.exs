defmodule VNI.Repo.Migrations.CreateMapVersions do
  use Ecto.Migration

  def change do
    create table(:map_versions) do
      add :state, :string, null: false
      add :level, :string, null: false
      add :congress, :integer
      add :effective_from, :date, null: false
      add :effective_until, :date
      add :authority, :string
      add :controlling_party, :string
      add :source_url, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:map_versions, [:state, :level, :congress, :effective_from])
    create index(:map_versions, [:state, :level])
  end
end
