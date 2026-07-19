defmodule VNI.Atlas do
  @moduledoc """
  Districts, geometries, and map versions.

  The core invariant: districts are always addressed through a map version.
  The "current" map for a state/level is the version with `effective_until`
  nil. Public lookups (by slug) resolve against current maps only; history
  stays queryable by map version id.
  """

  import Ecto.Query

  alias VNI.Repo
  alias VNI.Atlas.{District, MapVersion}

  ## Map versions

  def create_map_version(attrs) do
    %MapVersion{}
    |> MapVersion.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Idempotent upsert keyed on the map-version source identity. Reruns also
  re-assert the version's effectivity window: a rerun of a historical
  ingest heals a wrong `effective_until`, and a rerun of a current ingest
  re-declares the version open-ended.
  """
  def upsert_map_version(attrs) do
    %MapVersion{}
    |> MapVersion.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:source_url, :effective_until, :updated_at]},
      conflict_target: [:state, :level, :congress, :effective_from],
      returning: true
    )
  end

  @doc """
  Raise unless a map version with these attrs can be ingested without
  corrupting the state's timeline.

  Ingesting as current (`effective_until` nil) requires the state's
  existing current map, if any, to carry the same congress and
  `effective_from` — otherwise two versions would compete for current.
  Ingesting as historical (`effective_until` set) requires the existing
  current map, if any, to belong to a strictly later congress: a closed
  version must never land at or after the congress the state currently
  points at.
  """
  def assert_ingestable_map_version!(%{state: state, level: level, congress: congress} = attrs)
      when is_integer(congress) do
    current = current_map_version(state, level)
    effective_until = Map.get(attrs, :effective_until)

    cond do
      current == nil ->
        :ok

      effective_until == nil ->
        if current.congress == congress and
             current.effective_from == Map.fetch!(attrs, :effective_from) do
          :ok
        else
          raise """
          #{state} already has current map version #{current.id} for Congress \
          #{current.congress}; refusing to create an ambiguous current map
          """
        end

      is_integer(current.congress) and current.congress > congress ->
        :ok

      true ->
        raise """
        #{state} historical ingest for Congress #{congress} conflicts with \
        current map version #{current.id} (Congress #{inspect(current.congress)}); \
        supersede the current map before ingesting this congress as history
        """
    end
  end

  def get_map_version!(id), do: Repo.get!(MapVersion, id)

  @doc "The map currently in effect for a state at a level, or nil."
  def current_map_version(state, level) do
    from(mv in MapVersion,
      where: mv.state == ^state and mv.level == ^level and is_nil(mv.effective_until)
    )
    |> Repo.one()
  end

  def list_current_map_versions(level) do
    from(mv in MapVersion, where: mv.level == ^level and is_nil(mv.effective_until))
    |> Repo.all()
  end

  @doc "Every map version seated for a congress at a level, current or closed."
  def list_map_versions(congress, level \\ :congressional) when is_integer(congress) do
    from(mv in MapVersion,
      where: mv.congress == ^congress and mv.level == ^level,
      order_by: mv.state
    )
    |> Repo.all()
  end

  @doc """
  Close out a map version (a redraw happened). Sets `effective_until`;
  the successor version is created separately with its own districts.
  """
  def supersede_map_version(%MapVersion{} = map_version, %Date{} = effective_until) do
    map_version
    |> Ecto.Changeset.change(effective_until: effective_until)
    |> Repo.update()
  end

  ## Districts

  @doc """
  Idempotent upsert keyed on (map_version_id, slug) — ingest tasks are
  rerunnable by design.
  """
  def upsert_district(%MapVersion{} = map_version, attrs) do
    %District{map_version_id: map_version.id, state: map_version.state}
    |> District.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :map_version_id, :inserted_at]},
      conflict_target: [:map_version_id, :slug],
      returning: true
    )
  end

  def list_districts(%MapVersion{} = map_version) do
    from(d in District, where: d.map_version_id == ^map_version.id, order_by: [d.state, d.number])
    |> Repo.all()
  end

  @doc """
  The other districts sharing a district's map version, for the state context view.

  Scoped on `map_version_id` rather than state plus congress: map versions are
  already keyed on (state, level, congress), so this is correct for historical
  cohorts and for mid-decade redistricting without a second constraint to keep
  in sync. An at-large district returns `[]` — it has no siblings by definition.

  Geometry is coarsened to a ~1km tolerance because these paths are only ever
  drawn at state zoom, where finer detail is smaller than a pixel. The subject
  district keeps its full `geom_simplified` detail; it is shown magnified.
  """
  def list_sibling_geometries(%District{id: id, map_version_id: map_version_id}) do
    from(d in District,
      where: d.map_version_id == ^map_version_id and d.id != ^id,
      order_by: d.number,
      select: %{
        slug: d.slug,
        geom:
          type(
            fragment("ST_Multi(ST_SimplifyPreserveTopology(?, 0.01))", d.geom_simplified),
            Geo.PostGIS.Geometry
          )
      }
    )
    |> Repo.all()
  end

  @doc "Derive display geometry and geodesic measurements after geometry ingest."
  def refresh_district_geometries!(%MapVersion{} = map_version) do
    Repo.query!(
      """
      UPDATE districts
      SET geom_simplified = ST_Multi(ST_SimplifyPreserveTopology(geom, 0.005)),
          land_area_sqkm = ST_Area(geom::geography) / 1000000.0,
          perimeter_km = ST_Perimeter(geom::geography) / 1000.0,
          updated_at = NOW()
      WHERE map_version_id = $1
        AND geom IS NOT NULL
      """,
      [map_version.id]
    )

    :ok
  end

  @doc "Resolve a slug against current maps at a level. Returns nil if unknown."
  def get_district_by_slug(slug, level \\ :congressional) do
    from(d in District,
      join: mv in assoc(d, :map_version),
      where: d.slug == ^slug and mv.level == ^level and is_nil(mv.effective_until),
      preload: [:score, :profile, map_version: mv]
    )
    |> Repo.one()
  end

  @doc "All districts under current maps at a level, with scores and profiles."
  def list_current_districts(level \\ :congressional) do
    from(d in District,
      join: mv in assoc(d, :map_version),
      where: mv.level == ^level and is_nil(mv.effective_until),
      order_by: [d.state, d.number],
      preload: [:score, :profile, map_version: mv]
    )
    |> Repo.all()
  end
end
