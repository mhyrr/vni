defmodule VNI.Repo.Migrations.AddAuthorshipSourceToMapVersions do
  use Ecto.Migration

  def change do
    alter table(:map_versions) do
      add :authorship_source_url, :string
    end
  end
end
