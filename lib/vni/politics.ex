defmodule VNI.Politics do
  @moduledoc """
  Published political facts: incumbents, tenure, partisan lean, map
  authorship context. Facts only — the doctrine is exclusively
  anti-entrenchment, so nothing here takes a position beyond what the
  public record states.
  """

  import Ecto.Query

  alias VNI.Repo
  alias VNI.Atlas.District
  alias VNI.Politics.{DistrictProfile, StateCycle}

  @entrenchment_sorts [:tenure, :margin, :lean]

  # Mirrors the display field set in VNI.Scores.list_least_compact/2 — both
  # feed the same presenter, so the shapes must stay interchangeable.
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
  Idempotent upsert keyed on district — ingest tasks are rerunnable.

  Only the fields present in `attrs` are replaced on conflict, so the
  independent ingests that share this row (legislators, results, ACS)
  merge instead of clobbering each other.
  """
  def upsert_profile(%District{} = district, attrs) do
    changeset = DistrictProfile.changeset(%DistrictProfile{district_id: district.id}, attrs)
    replace = Map.keys(changeset.changes) ++ [:updated_at]

    Repo.insert(changeset,
      on_conflict: {:replace, replace},
      conflict_target: [:district_id],
      returning: true
    )
  end

  def get_profile(district_id), do: Repo.get_by(DistrictProfile, district_id: district_id)

  @doc """
  Current scored districts ordered by an entrenchment attribute, most
  entrenched first: longest tenure, widest last margin, or largest lean
  magnitude. Lean sorts by absolute deviation, so the safest red and blue
  seats interleave — the evidence stays symmetric by construction.

  Districts without the ingested fact sort last, never out.
  """
  def list_most_entrenched(attr, level \\ :congressional)

  def list_most_entrenched(attr, level) when attr in @entrenchment_sorts do
    from(d in District,
      join: s in assoc(d, :score),
      join: mv in assoc(d, :map_version),
      left_join: p in assoc(d, :profile),
      where:
        mv.level == ^level and is_nil(mv.effective_until) and
          not is_nil(s.polsby_popper),
      order_by: ^entrenchment_order(attr),
      order_by: [asc: d.state, asc: d.number],
      select: struct(d, ^@display_district_fields),
      preload: [profile: p, score: s, map_version: mv]
    )
    |> Repo.all()
  end

  def list_most_entrenched(attr, _level) do
    raise ArgumentError, "unsupported entrenchment sort: #{inspect(attr)}"
  end

  # Longest tenure = earliest first House year.
  defp entrenchment_order(:tenure),
    do: [asc_nulls_last: dynamic([d, s, mv, p], p.incumbent_since)]

  defp entrenchment_order(:margin),
    do: [desc_nulls_last: dynamic([d, s, mv, p], p.last_margin_pct)]

  defp entrenchment_order(:lean),
    do: [desc_nulls_last: dynamic([d, s, mv, p], fragment("ABS(?)", p.partisan_lean))]

  @doc "One state's seats–votes series, oldest cycle first."
  def state_history(state) do
    from(sc in StateCycle, where: sc.state == ^state, order_by: sc.cycle)
    |> Repo.all()
  end

  @doc """
  The most recent seats–votes row per state, as a state-keyed map.
  Feeds the /states index fact pair.
  """
  def latest_state_cycles do
    latest =
      from(sc in StateCycle,
        select: %{state: sc.state, cycle: max(sc.cycle)},
        group_by: sc.state
      )

    from(sc in StateCycle,
      join: l in subquery(latest),
      on: sc.state == l.state and sc.cycle == l.cycle
    )
    |> Repo.all()
    |> Map.new(&{&1.state, &1})
  end

  @doc """
  Partisan lean: weighted two-cycle average of the district's deviation
  from the nation. Positive = more Republican than the nation, negative =
  more Democratic (R+/D-). Inputs must be commensurable series — the
  results ingest feeds R shares of the two-party presidential vote, in
  percentage points (see `VNI.Politics.Results`).

  Our own published formula on public data — not Cook PVI, which is a
  licensed product. Weights favor the more recent cycle 3:1.
  """
  def partisan_lean(district_margins, national_margins)

  def partisan_lean([recent, prior], [nat_recent, nat_prior]) do
    0.75 * (recent - nat_recent) + 0.25 * (prior - nat_prior)
  end

  def partisan_lean([recent], [nat_recent]), do: recent - nat_recent
end
