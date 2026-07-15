defmodule VNI.Politics.DistrictProfile do
  @moduledoc """
  Published facts about a district: incumbent, tenure, margin, computed
  partisan lean, ACS population. Lean is our own formula from public
  presidential-results-by-CD data — never Cook PVI (licensed product).

  One row per district (which is map-version-scoped), filled by several
  independent ingests — each upsert replaces only the fields it provides,
  and each domain carries its own source citation.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "district_profiles" do
    belongs_to :district, VNI.Atlas.District
    field :incumbent_name, :string
    field :incumbent_party, Ecto.Enum, values: [:dem, :rep, :ind]
    field :incumbent_since, :integer
    field :last_margin_pct, :float
    field :partisan_lean, :float
    field :bioguide_id, :string
    field :incumbent_source_url, :string
    field :population, :integer
    field :voting_age_population, :integer
    field :acs_vintage, :integer
    field :population_source_url, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(profile, attrs) do
    profile
    |> cast(attrs, [
      :incumbent_name,
      :incumbent_party,
      :incumbent_since,
      :last_margin_pct,
      :partisan_lean,
      :bioguide_id,
      :incumbent_source_url,
      :population,
      :voting_age_population,
      :acs_vintage,
      :population_source_url
    ])
    |> foreign_key_constraint(:district_id)
    |> unique_constraint(:district_id)
  end
end
