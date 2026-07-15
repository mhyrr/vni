defmodule VNI.Repo.Migrations.AddPopulationToDistrictProfiles do
  use Ecto.Migration

  def change do
    alter table(:district_profiles) do
      add :population, :bigint
      add :voting_age_population, :bigint
      add :acs_vintage, :integer
      add :population_source_url, :string
    end
  end
end
