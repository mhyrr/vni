defmodule VNI.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :vni

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Load the derived data production cannot rebuild — see `VNI.Promotion`.

  Runs after migrations on every deploy, which is what keeps the ZIP
  crosswalk in step with the districts it was computed against: the pairs
  are only true of one map, so they ship with the code that serves them
  rather than by a separate errand someone has to remember.
  """
  def promote do
    load_app()

    {:ok, counts, _} =
      Ecto.Migrator.with_repo(VNI.Repo, fn _repo -> VNI.Promotion.load!() end)

    counts
  end

  @doc "Everything a deploy has to do before the new image serves traffic."
  def setup do
    migrate()
    promote()
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
