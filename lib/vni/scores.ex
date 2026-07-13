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

  Bump @methodology_version whenever a formula changes — published scores
  must be reproducible against a stated version.
  """

  import Ecto.Query

  alias VNI.Repo
  alias VNI.Atlas.District
  alias VNI.Scores.DistrictScore

  @methodology_version "2026.1"

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
      UPDATE district_scores ds SET
        polsby_popper = 4 * pi() * ST_Area(d.geom::geography)
          / NULLIF(power(ST_Perimeter(d.geom::geography), 2), 0),
        schwartzberg = 2 * pi() * sqrt(ST_Area(d.geom::geography) / pi())
          / NULLIF(ST_Perimeter(d.geom::geography), 0),
        reock = ST_Area(ST_Transform(d.geom, 5070))
          / NULLIF(ST_Area(ST_MinimumBoundingCircle(ST_Transform(d.geom, 5070))), 0),
        convex_hull = ST_Area(ST_Transform(d.geom, 5070))
          / NULLIF(ST_Area(ST_ConvexHull(ST_Transform(d.geom, 5070))), 0),
        updated_at = now()
      FROM districts d
      WHERE d.id = ds.district_id
        AND d.map_version_id = $1
        AND d.geom IS NOT NULL
      """,
      [map_version_id]
    )

    :ok
  end

  @doc """
  Composite + national rank across every district under a current map
  version at the given level. Min-max normalization is computed over that
  same set, so scores are only comparable within a methodology version and
  scoring pass.
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
      [Atom.to_string(level)]
    )

    :ok
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
      [map_version_id, @methodology_version]
    )
  end
end
