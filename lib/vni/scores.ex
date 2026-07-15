defmodule VNI.Scores do
  @moduledoc """
  The compactness scoring engine: Elixir orchestrating PostGIS SQL.

  Measurement rules (do not relax):
    * Area/perimeter in geography casts (`geom::geography`) — spheroidal,
      correct for AK/HI/PR, never raw 4326 degrees.
    * Constructions with no geography version (minimum bounding circle,
      convex hull) run in EPSG:5070 (CONUS Albers) via ST_Transform.

  All four metrics land in [0, 1], 1 = circle. Composite = mean of the four
  after min-max normalization across the current map set at a level;
  national_rank orders by composite descending (1 = most compact).

  At-large districts (number 0) keep their raw metrics but are excluded
  from normalization and ranking: their "shape" is the state border, drawn
  by nobody, so it is not evidence about a map-drawer (2026.2).

  Bump @methodology_version whenever a formula changes — published scores
  must be reproducible against a stated version.
  """

  import Ecto.Query

  alias VNI.Repo
  alias VNI.Atlas.District
  alias VNI.Scores.DistrictScore

  @methodology_version "2026.3"

  def methodology_version, do: @methodology_version

  @doc """
  Full scoring pass for the current map set at a level: raw metrics for
  every current map version, then normalize + rank nationally.
  """
  def score_current!(level \\ :congressional) do
    for mv <- VNI.Atlas.list_current_map_versions(level) do
      compute_metrics!(mv.id)
    end

    normalize_and_rank!(level)
    :ok
  end

  @doc "Compute the four raw metrics for every district in a map version."
  def compute_metrics!(map_version_id) do
    ensure_score_rows!(map_version_id)

    Repo.query!(
      """
      -- Transform and construct the hull once. The minimum enclosing circle
      -- of a geometry is exactly the minimum enclosing circle of its convex
      -- hull, while the hull has far fewer points for TIGER coastlines.
      WITH base AS MATERIALIZED (
        SELECT d.id,
          ST_Area(d.geom::geography) AS area_m2,
          ST_Perimeter(d.geom::geography) AS perimeter_m,
          ST_Transform(d.geom, 5070) AS geom_5070
        FROM districts d
        WHERE d.map_version_id = $1
          AND d.geom IS NOT NULL
      ),
      hulls AS MATERIALIZED (
        SELECT id, area_m2, perimeter_m,
          ST_Area(geom_5070) AS projected_area,
          ST_ConvexHull(geom_5070) AS hull
        FROM base
      ),
      measurements AS MATERIALIZED (
        SELECT id, area_m2, perimeter_m, projected_area,
          ST_Area(hull) AS hull_area,
          ST_Area(ST_MinimumBoundingCircle(hull)) AS circle_area
        FROM hulls
      )
      -- Each ratio is mathematically <= 1 (isoperimetric inequality; a shape
      -- never exceeds its hull or bounding circle), so LEAST(1.0, ...) only
      -- absorbs float noise from GEOS, which varies by PostGIS version.
      UPDATE district_scores ds SET
        polsby_popper = LEAST(1.0, 4 * pi() * m.area_m2
          / NULLIF(power(m.perimeter_m, 2), 0)),
        schwartzberg = LEAST(1.0, 2 * pi() * sqrt(m.area_m2 / pi())
          / NULLIF(m.perimeter_m, 0)),
        reock = LEAST(1.0, m.projected_area / NULLIF(m.circle_area, 0)),
        convex_hull = LEAST(1.0, m.projected_area / NULLIF(m.hull_area, 0)),
        updated_at = now()
      FROM measurements m
      WHERE m.id = ds.district_id
      """,
      [map_version_id],
      timeout: :infinity
    )

    :ok
  end

  @doc """
  Composite + national rank across every district under a current map
  version at the given level. Min-max normalization is computed over that
  same set, so scores are only comparable within a methodology version and
  scoring pass.

  At-large districts are excluded from the set entirely — they neither
  receive a composite/rank nor influence the min-max bounds — and any
  composite/rank they carry from an earlier methodology is cleared.
  """
  def normalize_and_rank!(level \\ :congressional) do
    Repo.query!(
      """
      WITH current_scores AS (
        SELECT ds.id, ds.polsby_popper, ds.reock, ds.convex_hull, ds.schwartzberg
        FROM district_scores ds
        JOIN districts d ON d.id = ds.district_id
        JOIN map_versions mv ON mv.id = d.map_version_id
        WHERE mv.level = $1
          AND mv.effective_until IS NULL
          AND d.number <> 0
          AND ds.polsby_popper IS NOT NULL
      ),
      bounds AS (
        SELECT
          min(polsby_popper) AS min_pp, max(polsby_popper) AS max_pp,
          min(reock) AS min_re, max(reock) AS max_re,
          min(convex_hull) AS min_ch, max(convex_hull) AS max_ch,
          min(schwartzberg) AS min_sc, max(schwartzberg) AS max_sc
        FROM current_scores
      ),
      normalized AS (
        SELECT cs.id,
          (
            coalesce((cs.polsby_popper - b.min_pp) / NULLIF(b.max_pp - b.min_pp, 0), 0.5) +
            coalesce((cs.reock - b.min_re) / NULLIF(b.max_re - b.min_re, 0), 0.5) +
            coalesce((cs.convex_hull - b.min_ch) / NULLIF(b.max_ch - b.min_ch, 0), 0.5) +
            coalesce((cs.schwartzberg - b.min_sc) / NULLIF(b.max_sc - b.min_sc, 0), 0.5)
          ) / 4.0 AS composite
        FROM current_scores cs
        CROSS JOIN bounds b
      ),
      ranked AS (
        SELECT id, composite, rank() OVER (ORDER BY composite DESC) AS rnk
        FROM normalized
      )
      UPDATE district_scores ds
      SET composite = r.composite, national_rank = r.rnk, updated_at = now()
      FROM ranked r
      WHERE ds.id = r.id
      """,
      [Atom.to_string(level)],
      timeout: :infinity
    )

    Repo.query!(
      """
      UPDATE district_scores ds
      SET composite = NULL, national_rank = NULL, updated_at = now()
      FROM districts d
      JOIN map_versions mv ON mv.id = d.map_version_id
      WHERE ds.district_id = d.id
        AND mv.level = $1
        AND mv.effective_until IS NULL
        AND d.number = 0
        AND (ds.composite IS NOT NULL OR ds.national_rank IS NOT NULL)
      """,
      [Atom.to_string(level)],
      timeout: :infinity
    )

    :ok
  end

  @doc "How many current districts hold a national rank (at-large excluded)."
  def ranked_count(level \\ :congressional) do
    from(d in District,
      join: s in assoc(d, :score),
      join: mv in assoc(d, :map_version),
      where: mv.level == ^level and is_nil(mv.effective_until) and not is_nil(s.national_rank)
    )
    |> Repo.aggregate(:count)
  end

  @doc "Ranked current districts (1 = most compact), scores and profiles preloaded."
  def list_ranked(level \\ :congressional) do
    from(d in District,
      join: s in assoc(d, :score),
      join: mv in assoc(d, :map_version),
      where: mv.level == ^level and is_nil(mv.effective_until) and not is_nil(s.national_rank),
      order_by: s.national_rank,
      preload: [:profile, score: s, map_version: mv]
    )
    |> Repo.all()
  end

  @sortable_metrics [:composite, :polsby_popper, :reock, :convex_hull, :schwartzberg]
  @display_district_fields [
    :id,
    :map_version_id,
    :state,
    :number,
    :slug,
    :geom_simplified,
    :land_area_sqkm,
    :perimeter_km
  ]

  @doc """
  Current scored districts ordered from least to most compact by one metric.
  At-large districts have no composite, so a composite sort places them
  last — present in the field, outside the ranking.
  """
  def list_least_compact(metric \\ :composite, level \\ :congressional)

  def list_least_compact(metric, level) when metric in @sortable_metrics do
    from(d in District,
      join: s in assoc(d, :score),
      join: mv in assoc(d, :map_version),
      where:
        mv.level == ^level and is_nil(mv.effective_until) and
          not is_nil(s.polsby_popper),
      order_by: [asc_nulls_last: field(s, ^metric), asc: d.state, asc: d.number],
      select: struct(d, ^@display_district_fields),
      preload: [:profile, score: s, map_version: mv]
    )
    |> Repo.all()
  end

  def list_least_compact(metric, _level) do
    raise ArgumentError, "unsupported compactness metric: #{inspect(metric)}"
  end

  @doc """
  A state's current scored districts, ordered by district number (at-large
  first). Feeds the `/states/:state` districts section — same display
  fields and preloads as `list_least_compact/2`, so both share a presenter.
  """
  def list_state_districts(state, level \\ :congressional) do
    from(d in District,
      join: s in assoc(d, :score),
      join: mv in assoc(d, :map_version),
      where:
        d.state == ^state and mv.level == ^level and is_nil(mv.effective_until) and
          not is_nil(s.polsby_popper),
      order_by: [asc: d.number],
      select: struct(d, ^@display_district_fields),
      preload: [:profile, score: s, map_version: mv]
    )
    |> Repo.all()
  end

  @doc "A current scored district trimmed to the fields needed by the public UI."
  def get_current_district(slug, level \\ :congressional) do
    from(d in District,
      join: s in assoc(d, :score),
      join: mv in assoc(d, :map_version),
      where:
        d.slug == ^slug and mv.level == ^level and is_nil(mv.effective_until) and
          not is_nil(s.polsby_popper),
      select: struct(d, ^@display_district_fields),
      preload: [:profile, score: s, map_version: mv]
    )
    |> Repo.one()
  end

  def get_score(district_id), do: Repo.get_by(DistrictScore, district_id: district_id)

  # One score row per district in the map version, stamped with the current
  # methodology version. Idempotent — reruns refresh in place.
  defp ensure_score_rows!(map_version_id) do
    Repo.query!(
      """
      INSERT INTO district_scores (district_id, methodology_version, inserted_at, updated_at)
      SELECT d.id, $2, now(), now()
      FROM districts d
      WHERE d.map_version_id = $1
      ON CONFLICT (district_id)
      DO UPDATE SET methodology_version = EXCLUDED.methodology_version, updated_at = now()
      """,
      [map_version_id, @methodology_version],
      timeout: :infinity
    )
  end
end
