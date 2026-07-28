defmodule VNI.Promotion do
  @moduledoc """
  Derived data that travels from a development machine to production.

  Three things cannot be rebuilt where they are served. The ZIP crosswalk
  is computed from 884 MB of ZCTA polygons, using GDAL and a 530 MB
  download; `last_margin_votes` comes out of the MEDSL results archive.
  `docs/deployment/fly.md` is explicit that ingests do not run inside the
  release, so the derived rows travel instead — three gzipped CSVs under
  `priv/promotion`, written by `mix vni.promote.export` and loaded by the
  release command on the next deploy.

  ## What travels is the answer, never the geometry that produced it

  Production resolves a ZIP through `Repo.get_by(Zcta, zcta5: ...)` and a
  join on `zcta_id`, and draws the shapes on `/find` from `districts`. It
  selects `zctas.geom` nowhere. Shipping the polygons would take the
  database from 343 MB to past a gigabyte, onto a 512 MB machine, to fill
  a column no query reads. `geom` is left out of every upsert rather than
  written as NULL, so a database that does hold the polygons keeps them.

  ## Natural keys, never row ids

  Rows are keyed on `zcta5` and district `slug`. The ids agree today —
  production was restored from a dump of this machine — but the crosswalk
  decides which seat a person is told they live in, and "the ids probably
  still line up" is not a foundation for that. A key that does not resolve
  raises; it never skips the row.

  ## Wholesale where the source is wholesale

  `VNI.Atlas.Postal.rebuild_crosswalk!/1` deletes the crosswalk and
  recomputes it, because the table is derived and the pairs are only true
  of the map they were computed against. Loading inherits that: the
  crosswalk is replaced inside one transaction, so a pair that no longer
  survives the sliver rule cannot linger and no reader sees the table
  empty. ZCTAs upsert, matching how the Census file is ingested.
  """

  import Ecto.Query
  require Logger

  alias NimbleCSV.RFC4180, as: CSV
  alias VNI.Atlas.{District, Zcta, ZctaDistrict}
  alias VNI.Politics.DistrictProfile
  alias VNI.Repo

  @headers %{
    zctas: ["zcta5", "area_sqkm", "vintage", "source_url"],
    crosswalk: ["zcta5", "district_slug", "overlap_sqkm", "zcta_share"],
    margins: ["district_slug", "last_margin_votes"]
  }

  @files %{
    zctas: "zctas.csv.gz",
    crosswalk: "crosswalk.csv.gz",
    margins: "margins.csv.gz"
  }

  @chunk 1_000

  @doc "Where the release reads its artifact from."
  def priv_dir, do: Application.app_dir(:vni, "priv/promotion")

  ## Export

  @doc """
  Write the three artifacts to `dir`, overwriting what is there.

  Rows come out ordered by their natural key so that re-exporting
  unchanged data produces a byte-identical file and the diff stays
  readable.
  """
  def export!(dir) do
    File.mkdir_p!(dir)

    %{
      zctas: write!(dir, :zctas, zcta_rows()),
      crosswalk: write!(dir, :crosswalk, crosswalk_rows()),
      margins: write!(dir, :margins, margin_rows())
    }
  end

  defp zcta_rows do
    Repo.all(
      from(z in Zcta,
        order_by: z.zcta5,
        select: [z.zcta5, z.area_sqkm, z.vintage, z.source_url]
      )
    )
  end

  defp crosswalk_rows do
    Repo.all(
      from(zd in ZctaDistrict,
        join: z in Zcta,
        on: z.id == zd.zcta_id,
        join: d in District,
        on: d.id == zd.district_id,
        order_by: [z.zcta5, d.slug],
        select: [z.zcta5, d.slug, zd.overlap_sqkm, zd.zcta_share]
      )
    )
  end

  # A profile with no margin says nothing that loading it could carry —
  # an unopposed or unscored seat reads the same absent on both sides.
  defp margin_rows do
    Repo.all(
      from(p in DistrictProfile,
        join: d in District,
        on: d.id == p.district_id,
        where: not is_nil(p.last_margin_votes),
        order_by: d.slug,
        select: [d.slug, p.last_margin_votes]
      )
    )
  end

  defp write!(dir, key, rows) do
    path = Path.join(dir, Map.fetch!(@files, key))

    data =
      [Map.fetch!(@headers, key) | rows]
      |> CSV.dump_to_iodata()
      |> IO.iodata_to_binary()
      |> :zlib.gzip()

    File.write!(path, data)

    {path, length(rows)}
  end

  ## Load

  @doc """
  Load every artifact in `dir` into the database.

  Idempotent: rerunning promotes the same rows to the same values, which
  is what lets this hang off the release command and no-op on a redeploy
  that changed no data.
  """
  def load!(dir \\ priv_dir()) do
    now = DateTime.utc_now(:second)

    zctas = load_zctas!(dir, now)
    districts = current_district_ids()
    crosswalk = load_crosswalk!(dir, districts, now)
    margins = load_margins!(dir, districts, now)

    counts = %{zctas: zctas, crosswalk: crosswalk, margins: margins}
    Logger.info("promotion loaded: #{inspect(counts)}")

    counts
  end

  # `geom` is deliberately absent from the replace list. A fresh row gets
  # NULL geometry, which production never reads; a database that has the
  # polygons keeps them.
  defp load_zctas!(dir, now) do
    dir
    |> read!(:zctas)
    |> Stream.map(fn [zcta5, area_sqkm, vintage, source_url] ->
      %{
        zcta5: zcta5,
        area_sqkm: float!(area_sqkm),
        vintage: int!(vintage),
        source_url: source_url,
        inserted_at: now,
        updated_at: now
      }
    end)
    |> Stream.chunk_every(@chunk)
    |> Enum.reduce(0, fn chunk, total ->
      {count, _} =
        Repo.insert_all(Zcta, chunk,
          on_conflict: {:replace, [:area_sqkm, :vintage, :source_url, :updated_at]},
          conflict_target: :zcta5
        )

      total + count
    end)
  end

  defp load_crosswalk!(dir, districts, now) do
    zctas = Repo.all(from(z in Zcta, select: {z.zcta5, z.id})) |> Map.new()

    rows =
      dir
      |> read!(:crosswalk)
      |> Enum.map(fn [zcta5, slug, overlap_sqkm, zcta_share] ->
        %{
          zcta_id: fetch!(zctas, zcta5, "ZCTA"),
          district_id: fetch!(districts, slug, "district"),
          overlap_sqkm: float!(overlap_sqkm),
          zcta_share: float!(zcta_share),
          inserted_at: now,
          updated_at: now
        }
      end)

    {:ok, count} =
      Repo.transaction(
        fn ->
          Repo.delete_all(ZctaDistrict)

          rows
          |> Stream.chunk_every(@chunk)
          |> Enum.reduce(0, fn chunk, total ->
            {count, _} = Repo.insert_all(ZctaDistrict, chunk)
            total + count
          end)
        end,
        timeout: :infinity
      )

    count
  end

  defp load_margins!(dir, districts, now) do
    dir
    |> read!(:margins)
    |> Enum.reduce(0, fn [slug, votes], total ->
      district_id = fetch!(districts, slug, "district")

      {count, _} =
        Repo.update_all(
          from(p in DistrictProfile, where: p.district_id == ^district_id),
          set: [last_margin_votes: int!(votes), updated_at: now]
        )

      if count == 0 do
        raise """
        no district profile for #{slug}.

        Margins promote onto profiles that are already there; they do not
        create them. A missing profile means this database is behind the
        one the artifact was exported from.
        """
      end

      total + count
    end)
  end

  # Slugs are unique per map version, so this is only unambiguous across
  # the current congressional maps — which is the whole crosswalk, by
  # construction. `Map.new/1` would drop a collision silently, and a
  # silently dropped district is a ZIP quietly routed to the wrong seat,
  # so the size is checked rather than assumed.
  defp current_district_ids do
    query =
      from(d in District,
        join: m in assoc(d, :map_version),
        where: is_nil(m.effective_until) and m.level == :congressional
      )

    ids = query |> select([d], {d.slug, d.id}) |> Repo.all() |> Map.new()
    total = Repo.aggregate(query, :count)

    if map_size(ids) != total do
      raise "#{total} current districts collapse to #{map_size(ids)} slugs; slugs are not unique"
    end

    ids
  end

  defp fetch!(index, key, what) do
    case Map.fetch(index, key) do
      {:ok, id} ->
        id

      :error ->
        raise """
        no #{what} for #{inspect(key)} in this database.

        The artifact was exported against different data. Re-export from a
        machine whose districts match production, or promote the districts
        first — a crosswalk is only true of the map it was computed against.
        """
    end
  end

  ## Reading

  defp read!(dir, key) do
    path = Path.join(dir, Map.fetch!(@files, key))

    unless File.exists?(path) do
      raise "no promotion artifact at #{path}; run `mix vni.promote.export`"
    end

    [header | rows] =
      path
      |> File.read!()
      |> :zlib.gunzip()
      |> CSV.parse_string(skip_headers: false)

    expected = Map.fetch!(@headers, key)

    if header != expected do
      raise "#{path} has columns #{inspect(header)}, expected #{inspect(expected)}"
    end

    rows
  end

  defp float!(""), do: nil
  defp float!(value), do: String.to_float(value)

  defp int!(""), do: nil
  defp int!(value), do: String.to_integer(value)
end
