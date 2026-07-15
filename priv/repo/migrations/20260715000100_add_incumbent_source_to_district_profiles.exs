defmodule VNI.Repo.Migrations.AddIncumbentSourceToDistrictProfiles do
  use Ecto.Migration

  def change do
    alter table(:district_profiles) do
      add :incumbent_source_url, :string
    end
  end
end
