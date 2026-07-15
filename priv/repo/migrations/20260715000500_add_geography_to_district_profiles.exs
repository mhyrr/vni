defmodule VNI.Repo.Migrations.AddGeographyToDistrictProfiles do
  use Ecto.Migration

  def change do
    alter table(:district_profiles) do
      add :counties, {:array, :map}
      add :places, {:array, :map}
      add :geography_source_url, :string
    end
  end
end
