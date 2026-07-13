defmodule VNI.Repo.Migrations.CreateDistricts do
  use Ecto.Migration

  def change do
    create table(:districts) do
      add :map_version_id, references(:map_versions, on_delete: :delete_all), null: false
      add :state, :string, null: false
      add :number, :integer, null: false
      add :slug, :string, null: false
      add :geom, :"geometry(MultiPolygon, 4326)"
      add :geom_simplified, :"geometry(MultiPolygon, 4326)"
      add :land_area_sqkm, :float
      add :perimeter_km, :float

      timestamps(type: :utc_datetime)
    end

    create unique_index(:districts, [:map_version_id, :slug])
    create unique_index(:districts, [:map_version_id, :state, :number])
    create index(:districts, [:slug])

    execute(
      "CREATE INDEX districts_geom_idx ON districts USING GIST (geom)",
      "DROP INDEX districts_geom_idx"
    )
  end
end
