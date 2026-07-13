defmodule VNI.Atlas.District do
  @moduledoc """
  One district under one map version.

  Canonical geometry is MultiPolygon in EPSG:4326. All measurement happens
  in geography casts or EPSG:5070 — never raw 4326 degrees (see VNI.Scores).
  `geom_simplified` is precomputed at ingest for direct GeoJSON serving.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "districts" do
    belongs_to :map_version, VNI.Atlas.MapVersion
    field :state, :string
    field :number, :integer
    field :slug, :string
    field :geom, Geo.PostGIS.Geometry
    field :geom_simplified, Geo.PostGIS.Geometry
    field :land_area_sqkm, :float
    field :perimeter_km, :float

    has_one :score, VNI.Scores.DistrictScore
    has_one :profile, VNI.Politics.DistrictProfile

    timestamps(type: :utc_datetime)
  end

  def changeset(district, attrs) do
    district
    |> cast(attrs, [
      :state,
      :number,
      :slug,
      :geom,
      :geom_simplified,
      :land_area_sqkm,
      :perimeter_km
    ])
    |> validate_required([:state, :number])
    |> put_slug()
    |> validate_required([:slug])
    |> foreign_key_constraint(:map_version_id)
    |> unique_constraint([:map_version_id, :slug])
    |> unique_constraint([:map_version_id, :state, :number])
  end

  @doc ~S|Canonical slug: "tx-33". At-large districts use number 0: "wy-0".|
  def build_slug(state, number) when is_binary(state) and is_integer(number) do
    "#{String.downcase(state)}-#{number}"
  end

  defp put_slug(changeset) do
    case get_field(changeset, :slug) do
      nil ->
        with state when is_binary(state) <- get_field(changeset, :state),
             number when is_integer(number) <- get_field(changeset, :number) do
          put_change(changeset, :slug, build_slug(state, number))
        else
          _ -> changeset
        end

      _ ->
        changeset
    end
  end
end
