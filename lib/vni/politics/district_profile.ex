defmodule VNI.Politics.DistrictProfile do
  @moduledoc """
  Published political facts about a district: incumbent, tenure, margin,
  computed partisan lean. Lean is our own formula from public
  presidential-results-by-CD data — never Cook PVI (licensed product).
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
      :bioguide_id
    ])
    |> foreign_key_constraint(:district_id)
    |> unique_constraint(:district_id)
  end
end
