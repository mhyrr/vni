defmodule VNI.Scores.DistrictScore do
  @moduledoc """
  Compactness metrics for one district. All four raw metrics are in [0, 1]
  where 1 is a perfect circle. Composite is the mean of the four after
  min-max normalization across the current national map set; national_rank
  is 1 = most compact.

  Compactness is a shape metric, not a gerrymander metric — the methodology
  page owns that caveat, and this module's numbers must never be presented
  without it.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "district_scores" do
    belongs_to :district, VNI.Atlas.District
    field :polsby_popper, :float
    field :reock, :float
    field :convex_hull, :float
    field :schwartzberg, :float
    field :composite, :float
    field :national_rank, :integer
    field :methodology_version, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(score, attrs) do
    score
    |> cast(attrs, [
      :polsby_popper,
      :reock,
      :convex_hull,
      :schwartzberg,
      :composite,
      :national_rank,
      :methodology_version
    ])
    |> foreign_key_constraint(:district_id)
    |> unique_constraint(:district_id)
  end
end
