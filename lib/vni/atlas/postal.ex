defmodule VNI.Atlas.Postal do
  @moduledoc """
  ZIP to district, computed rather than looked up.

  A ZIP code is not a district and is not a shape. USPS ZIPs are delivery
  routes; the Census approximates them as ZCTAs by assigning each census
  block to the ZIP most of its addresses use. We ingest those polygons
  through the same TIGER pipeline that loads the districts and intersect
  the two ourselves, so the crosswalk carries the same provenance as
  everything else here — our own method, on published geometry, citable.

  The alternative was a third-party ZIP-to-district table. Every other
  number on this site is sourced and reproducible; a crosswalk that
  silently picked the largest district in a ZIP would be the one
  unsourced guess in the building.

  ## Measurement

  Per the project's CRS rule: the intersection is a *construction*, so it
  runs in EPSG:5070, and its area is then measured with a geography cast
  so Alaska and Hawaii are not quietly wrong. A ZCTA wholly inside one
  district skips the construction entirely — its overlap is its own area,
  exactly.

  ## The sliver rule

  `ST_Intersects` is true where two polygons merely touch, and ZCTA and
  district boundaries run along the same census blocks for hundreds of
  miles. Without a floor, every ZIP along a district line would offer its
  neighbour as a choice on the strength of a rounding error. A pair is
  kept only where the overlap is at least `minimum_share/0` of the ZCTA.
  Published on /methodology with every other rule this site computes.

  ## Never auto-pick

  Where a ZIP spans more than one seat, the caller shows the choices and
  the reader picks. Ordering by overlap is a convenience, not an answer:
  the largest slice of a ZIP's *area* is not necessarily where its people
  are, and pretending otherwise would put a guess where a fact goes.
  """

  import Ecto.Query

  alias VNI.Atlas.{District, Tiger, Zcta}
  alias VNI.Repo

  @vintage 2025
  @archive "tl_2025_us_zcta520.zip"

  # A pair survives at half a percent of the ZCTA's area. Measured against
  # the real crosswalk: boundary slivers land orders of magnitude below
  # this, and genuine splits land well above it.
  @minimum_share 0.005

  # TIGER renames this column each decennial vintage.
  @code_keys ~w(ZCTA5CE20 ZCTA5CE10 ZCTA5CE)

  def vintage, do: @vintage
  def minimum_share, do: @minimum_share

  def source_url do
    "#{Tiger.source_root()}/TIGER#{@vintage}/ZCTA520/#{@archive}"
  end

  ## Ingest

  @doc """
  Download and load every ZCTA polygon. Idempotent — reruns upsert on the
  five-digit code. The archive is ~530 MB and is cached like the district
  archives beside it.
  """
  def ingest!(opts \\ []) do
    cache_dir = Keyword.get(opts, :cache_dir, default_cache_dir())
    force_download? = Keyword.get(opts, :force_download, false)
    File.mkdir_p!(cache_dir)

    archive = Path.join(cache_dir, @archive)
    Tiger.download!(source_url(), archive, force_download?)
    geojson = Tiger.to_geojson_sequence!(archive, "zcta#{@vintage}")

    try do
      count = import_features!(geojson)
      refresh_areas!()
      count
    after
      File.rm(geojson)
    end
  end

  defp import_features!(path) do
    now = DateTime.utc_now(:second)
    source = source_url()

    path
    |> Tiger.stream_features!()
    |> Stream.map(fn feature ->
      properties = Map.fetch!(feature, "properties")

      %{
        zcta5: code!(properties),
        geom:
          feature |> Map.fetch!("geometry") |> Geo.JSON.decode!() |> Tiger.as_multi_polygon!(),
        vintage: @vintage,
        source_url: source,
        inserted_at: now,
        updated_at: now
      }
    end)
    |> Stream.chunk_every(500)
    |> Enum.reduce(0, fn chunk, total ->
      {count, _} =
        Repo.insert_all(Zcta, chunk,
          on_conflict: {:replace, [:geom, :vintage, :source_url, :updated_at]},
          conflict_target: :zcta5
        )

      total + count
    end)
  end

  defp code!(properties) do
    Enum.find_value(@code_keys, fn key -> Map.get(properties, key) end) ||
      raise "no ZCTA code column in #{inspect(Map.keys(properties))}"
  end

  @doc "Recompute every ZCTA's own area, the denominator of every share."
  def refresh_areas! do
    Repo.query!(
      """
      UPDATE zctas
      SET area_sqkm = ST_Area(geom::geography) / 1000000.0
      WHERE geom IS NOT NULL
      """,
      [],
      timeout: :infinity
    )

    :ok
  end

  ## The crosswalk

  @doc """
  Rebuild the ZCTA-to-district crosswalk against the current maps.

  Wholesale, not incremental: the table is derived, so recomputing it is
  cheaper to reason about than keeping it in step. Run after a district
  ingest — the pairs are only true of the map they were computed against.
  """
  def rebuild_crosswalk!(opts \\ []) do
    minimum_share = Keyword.get(opts, :minimum_share, @minimum_share)

    # Every share divides by this. Without the guard a missing area sends
    # each row out through the `> 0` filter and the crosswalk comes back
    # empty with nothing to say about why.
    missing = Repo.aggregate(from(z in Zcta, where: is_nil(z.area_sqkm)), :count)

    if missing > 0 do
      raise "#{missing} ZCTAs have no area; run VNI.Atlas.Postal.refresh_areas!/0 first"
    end

    Repo.query!("DELETE FROM zcta_districts", [], timeout: :infinity)

    %{num_rows: rows} =
      Repo.query!(
        """
        INSERT INTO zcta_districts
          (zcta_id, district_id, overlap_sqkm, zcta_share, inserted_at, updated_at)
        SELECT
          z.id,
          d.id,
          overlap.sqkm,
          overlap.sqkm / z.area_sqkm,
          now(),
          now()
        FROM zctas z
        JOIN districts d ON ST_Intersects(z.geom, d.geom)
        JOIN map_versions mv
          ON mv.id = d.map_version_id AND mv.effective_until IS NULL
        CROSS JOIN LATERAL (
          SELECT CASE
            -- Wholly inside: the overlap is the ZCTA, no construction needed.
            WHEN ST_CoveredBy(z.geom, d.geom) THEN z.area_sqkm
            ELSE ST_Area(
                   ST_Transform(
                     ST_CollectionExtract(
                       ST_Intersection(
                         ST_Transform(ST_MakeValid(z.geom), 5070),
                         ST_Transform(ST_MakeValid(d.geom), 5070)
                       ),
                       3
                     ),
                     4326
                   )::geography
                 ) / 1000000.0
          END AS sqkm
        ) AS overlap
        WHERE z.area_sqkm > 0
          AND overlap.sqkm / z.area_sqkm >= $1
        """,
        [minimum_share],
        timeout: :infinity
      )

    rows
  end

  ## Resolution

  @doc """
  The districts a ZIP falls in, most overlap first.

    * `{:ok, [match]}` — one entry per district, `match.zcta_share` the
      fraction of the ZCTA inside it
    * `{:error, :malformed}` — not five digits
    * `{:error, :unknown}` — no such ZCTA in the Census file
    * `{:error, :no_district}` — a real ZCTA with no voting district:
      Washington DC and the territories, which elect delegates who cannot
      vote on final passage. That is a fact about the seat, not a failure
      of the lookup, and the caller says so.
  """
  def resolve(zip) when is_binary(zip) do
    case normalize(zip) do
      {:ok, zcta5} -> lookup(zcta5)
      :error -> {:error, :malformed}
    end
  end

  def resolve(_zip), do: {:error, :malformed}

  @doc """
  Reduce user input to a five-digit ZCTA code, or `:error`.

  Accepts ZIP+4 — people paste what is on their mail — and nothing else.
  """
  def normalize(zip) when is_binary(zip) do
    # Five digits, nine digits, or five-dash-four. Nothing else: a
    # half-typed ZIP+4 has a valid five-digit prefix, and silently
    # resolving it would be answering a question nobody asked clearly.
    case String.replace(zip, ~r/\s/, "") do
      <<digits::binary-size(5)>> ->
        take_five(digits, digits)

      <<digits::binary-size(5), "-", plus_four::binary-size(4)>> ->
        take_five(digits <> plus_four, digits)

      <<digits::binary-size(5), plus_four::binary-size(4)>> ->
        take_five(digits <> plus_four, digits)

      _other ->
        :error
    end
  end

  def normalize(_zip), do: :error

  defp take_five(all, first_five) do
    if String.match?(all, ~r/^\d+$/), do: {:ok, first_five}, else: :error
  end

  defp lookup(zcta5) do
    case Repo.get_by(Zcta, zcta5: zcta5) do
      nil ->
        {:error, :unknown}

      zcta ->
        case matches(zcta) do
          [] -> {:error, :no_district}
          matches -> {:ok, matches}
        end
    end
  end

  defp matches(zcta) do
    from(zd in VNI.Atlas.ZctaDistrict,
      join: d in District,
      on: d.id == zd.district_id,
      where: zd.zcta_id == ^zcta.id,
      order_by: [desc: zd.zcta_share],
      preload: [district: {d, [:score, :profile, :map_version]}],
      select: zd
    )
    |> Repo.all()
    |> Enum.map(fn zd ->
      %{district: zd.district, zcta_share: zd.zcta_share, overlap_sqkm: zd.overlap_sqkm}
    end)
  end

  ## Counts, for the methodology page and the ingest task

  @doc "How many ZCTAs are loaded, and how many seats they resolve to."
  def coverage do
    seats_per_zcta =
      from(zd in VNI.Atlas.ZctaDistrict,
        group_by: zd.zcta_id,
        select: %{seats: count(zd.district_id)}
      )

    by_seats =
      from(z in subquery(seats_per_zcta),
        group_by: z.seats,
        select: {z.seats, count(z.seats)}
      )
      |> Repo.all()
      |> Map.new()

    resolved = by_seats |> Map.values() |> Enum.sum()
    single = Map.get(by_seats, 1, 0)
    zctas = Repo.aggregate(Zcta, :count)

    %{
      zctas: zctas,
      resolved: resolved,
      single: single,
      split: resolved - single,
      unresolved: zctas - resolved,
      by_seats: by_seats
    }
  end

  defp default_cache_dir, do: Path.expand("priv/repo/data/tiger/zcta#{@vintage}")
end
