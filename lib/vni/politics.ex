defmodule VNI.Politics do
  @moduledoc """
  Published political facts: incumbents, tenure, partisan lean, map
  authorship context. Facts only — the doctrine is exclusively
  anti-entrenchment, so nothing here takes a position beyond what the
  public record states.
  """

  alias VNI.Repo
  alias VNI.Atlas.District
  alias VNI.Politics.DistrictProfile

  @doc "Idempotent upsert keyed on district — legislator ingest is rerunnable."
  def upsert_profile(%District{} = district, attrs) do
    %DistrictProfile{district_id: district.id}
    |> DistrictProfile.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :district_id, :inserted_at]},
      conflict_target: [:district_id],
      returning: true
    )
  end

  def get_profile(district_id), do: Repo.get_by(DistrictProfile, district_id: district_id)

  @doc """
  Partisan lean from presidential results by CD: weighted two-cycle average
  of the district's margin relative to the national margin. Positive =
  more Republican than the nation, negative = more Democratic (R+/D-).

  Our own published formula on public data — not Cook PVI, which is a
  licensed product. Weights favor the more recent cycle 3:1.
  """
  def partisan_lean(district_margins, national_margins)

  def partisan_lean([recent, prior], [nat_recent, nat_prior]) do
    0.75 * (recent - nat_recent) + 0.25 * (prior - nat_prior)
  end

  def partisan_lean([recent], [nat_recent]), do: recent - nat_recent
end
