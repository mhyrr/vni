defmodule VNI.Atlas.MapVersion do
  @moduledoc """
  A districting map for one state at one level, bounded in time.

  "TX-33" is not a stable identifier — mid-decade redistricting is live.
  "TX-33 under the map effective for the 120th Congress" is. Districts
  always hang off a map version; the current map is the one whose
  `effective_until` is nil.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "map_versions" do
    field :state, :string
    field :level, Ecto.Enum, values: [:congressional, :state_leg, :local]
    field :congress, :integer
    field :effective_from, :date
    field :effective_until, :date

    field :authority, Ecto.Enum,
      values: [
        :legislature,
        :independent_commission,
        :politician_commission,
        :court,
        :special_master
      ]

    field :controlling_party, Ecto.Enum, values: [:dem, :rep, :split, :nonpartisan]
    field :source_url, :string
    field :authorship_source_url, :string

    has_many :districts, VNI.Atlas.District

    timestamps(type: :utc_datetime)
  end

  def changeset(map_version, attrs) do
    map_version
    |> cast(attrs, [
      :state,
      :level,
      :congress,
      :effective_from,
      :effective_until,
      :authority,
      :controlling_party,
      :source_url,
      :authorship_source_url
    ])
    |> validate_required([:state, :level, :effective_from])
    |> validate_format(:state, ~r/^[A-Z]{2}$/, message: "must be a two-letter USPS code")
    |> unique_constraint([:state, :level, :congress, :effective_from])
  end
end
