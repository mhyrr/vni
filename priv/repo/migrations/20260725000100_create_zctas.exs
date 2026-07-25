defmodule VNI.Repo.Migrations.CreateZctas do
  use Ecto.Migration

  def change do
    create table(:zctas) do
      add :zcta5, :string, null: false
      add :geom, :"geometry(MultiPolygon, 4326)"
      # The polygon's own area, water included — TIGER ZCTAs are drawn
      # around blocks, not coastlines. Both sides of every share use it,
      # so the ratio stays self-consistent.
      add :area_sqkm, :float
      add :vintage, :integer, null: false
      add :source_url, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:zctas, [:zcta5])

    execute(
      "CREATE INDEX zctas_geom_idx ON zctas USING GIST (geom)",
      "DROP INDEX zctas_geom_idx"
    )

    # The crosswalk is derived, not ingested: one row per ZCTA-district
    # pair that survives the sliver rule, with the overlap that earned it.
    # `district_id` is map-version-scoped, so a redraw drops the rows for
    # the retired districts with them — the crosswalk can never outlive
    # the map it was computed against.
    create table(:zcta_districts) do
      add :zcta_id, references(:zctas, on_delete: :delete_all), null: false
      add :district_id, references(:districts, on_delete: :delete_all), null: false
      add :overlap_sqkm, :float, null: false
      add :zcta_share, :float, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:zcta_districts, [:zcta_id, :district_id])
    create index(:zcta_districts, [:district_id])
  end
end
