defmodule VNI.Politics.StateCycle do
  @moduledoc """
  One state's House delegation and presidential two-party vote for one
  election cycle — the statewide seats–votes series, 1976–2024.

  The pair is published as two facts side by side, never as a single
  synthesized number: seat counts come from MEDSL House general winners,
  `pres_r_share` is the R share of the state's two-party presidential
  vote from MEDSL President. Midterm cycles carry seats only —
  `pres_r_share` stays nil rather than interpolated, because
  interpolation is modeling and the series publishes measurements.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "state_cycle_results" do
    field :state, :string
    field :cycle, :integer
    field :seats_dem, :integer, default: 0
    field :seats_rep, :integer, default: 0
    field :seats_other, :integer, default: 0
    field :pres_r_share, :float
    field :seats_source_url, :string
    field :pres_source_url, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(state_cycle, attrs) do
    state_cycle
    |> cast(attrs, [
      :state,
      :cycle,
      :seats_dem,
      :seats_rep,
      :seats_other,
      :pres_r_share,
      :seats_source_url,
      :pres_source_url
    ])
    |> validate_required([:state, :cycle, :seats_source_url])
    |> unique_constraint([:state, :cycle])
  end

  def total_seats(%__MODULE__{} = sc), do: sc.seats_dem + sc.seats_rep + sc.seats_other
end
