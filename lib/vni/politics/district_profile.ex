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
    field :last_margin_cycle, :integer
    field :last_margin_party, Ecto.Enum, values: [:dem, :rep, :ind]
    field :margin_source_url, :string
    field :partisan_lean, :float
    field :pres_share_2024, :float
    field :pres_share_2020, :float
    field :lean_source_url, :string
    field :bioguide_id, :string
    field :incumbent_source_url, :string
    field :population, :integer
    field :voting_age_population, :integer
    field :acs_vintage, :integer
    field :population_source_url, :string
    field :counties, {:array, :map}
    field :places, {:array, :map}
    field :geography_source_url, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(profile, attrs) do
    profile
    |> cast(attrs, [
      :incumbent_name,
      :incumbent_party,
      :incumbent_since,
      :last_margin_pct,
      :last_margin_cycle,
      :last_margin_party,
      :margin_source_url,
      :partisan_lean,
      :pres_share_2024,
      :pres_share_2020,
      :lean_source_url,
      :bioguide_id,
      :incumbent_source_url,
      :population,
      :voting_age_population,
      :acs_vintage,
      :population_source_url,
      :counties,
      :places,
      :geography_source_url
    ])
    |> foreign_key_constraint(:district_id)
    |> unique_constraint(:district_id)
  end
end
