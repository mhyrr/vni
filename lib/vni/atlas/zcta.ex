defmodule VNI.Atlas.Zcta do
  @moduledoc """
  One Census ZIP Code Tabulation Area.

  A ZCTA is not a ZIP code. ZIP codes are USPS delivery routes — lines
  along streets, with no area and no legal boundary — and the Census
  builds ZCTAs by assigning each census block to the ZIP code most of its
  addresses use. That approximation is the only published polygon a ZIP
  has, and saying so is part of citing it honestly.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "zctas" do
    field :zcta5, :string
    field :geom, Geo.PostGIS.Geometry
    field :area_sqkm, :float
    field :vintage, :integer
    field :source_url, :string

    has_many :zcta_districts, VNI.Atlas.ZctaDistrict
    has_many :districts, through: [:zcta_districts, :district]

    timestamps(type: :utc_datetime)
  end

  def changeset(zcta, attrs) do
    zcta
    |> cast(attrs, [:zcta5, :geom, :area_sqkm, :vintage, :source_url])
    |> validate_required([:zcta5, :geom, :vintage, :source_url])
    |> validate_format(:zcta5, ~r/^\d{5}$/, message: "must be five digits")
    |> unique_constraint(:zcta5)
  end
end
