defmodule VNI.Repo.Migrations.AddResultsToDistrictProfiles do
  use Ecto.Migration

  def change do
    alter table(:district_profiles) do
      add :last_margin_cycle, :integer
      add :last_margin_party, :string
      add :margin_source_url, :string
      add :lean_source_url, :string
    end
  end
end
