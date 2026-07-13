defmodule VNI.Repo.Migrations.CreateDistrictScores do
  use Ecto.Migration

  def change do
    create table(:district_scores) do
      add :district_id, references(:districts, on_delete: :delete_all), null: false
      add :polsby_popper, :float
      add :reock, :float
      add :convex_hull, :float
      add :schwartzberg, :float
      add :composite, :float
      add :national_rank, :integer
      add :methodology_version, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:district_scores, [:district_id])
  end
end
