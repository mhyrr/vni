defmodule VNI.Repo.Migrations.EnableExtensions do
  use Ecto.Migration

  def up do
    execute "CREATE EXTENSION IF NOT EXISTS postgis"
    execute "CREATE EXTENSION IF NOT EXISTS citext"
  end

  def down do
    execute "DROP EXTENSION IF EXISTS citext"
    execute "DROP EXTENSION IF EXISTS postgis"
  end
end
