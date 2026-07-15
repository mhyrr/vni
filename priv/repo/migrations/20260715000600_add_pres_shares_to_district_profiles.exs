defmodule VNI.Repo.Migrations.AddPresSharesToDistrictProfiles do
  use Ecto.Migration

  def change do
    alter table(:district_profiles) do
      add :pres_share_2024, :float
      add :pres_share_2020, :float
    end
  end
end
