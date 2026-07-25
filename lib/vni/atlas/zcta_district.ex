defmodule VNI.Atlas.ZctaDistrict do
  @moduledoc """
  One ZCTA's overlap with one congressional district.

  Derived, never ingested: `VNI.Atlas.Postal.rebuild_crosswalk!/0` computes
  these from the two geometries we already publish. `zcta_share` is the
  fraction of the ZCTA's area inside the district, and it is what orders
  the choices when a ZIP spans more than one seat.
  """

  use Ecto.Schema

  schema "zcta_districts" do
    belongs_to :zcta, VNI.Atlas.Zcta
    belongs_to :district, VNI.Atlas.District

    field :overlap_sqkm, :float
    field :zcta_share, :float

    timestamps(type: :utc_datetime)
  end
end
