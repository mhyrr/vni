defmodule VNIWeb.PreviewData do
  @moduledoc """
  Illustrative records for the interface prototype.

  None of these values are published VNI analysis. This module is deleted when
  the ingestion pipeline supplies production district data.
  """

  @districts [
    %{
      slug: "md-03",
      label: "MD–03",
      state: "Maryland",
      party: :dem,
      compactness: 18,
      compactness_rank: 418,
      map_bias: 72,
      turnover: 1,
      tenure: 19,
      margin: 31,
      lean: "D+18",
      neighbor_delta: -24,
      authority: "Legislature",
      shape: :coil,
      history_summary: "D held · D held · D held · D held"
    },
    %{
      slug: "oh-09",
      label: "OH–09",
      state: "Ohio",
      party: :dem,
      compactness: 24,
      compactness_rank: 402,
      map_bias: 64,
      turnover: 2,
      tenure: 7,
      margin: 13,
      lean: "D+4",
      neighbor_delta: -18,
      authority: "Commission",
      shape: :ribbon,
      history_summary: "D held · D held · R gain · D gain"
    },
    %{
      slug: "tx-35",
      label: "TX–35",
      state: "Texas",
      party: :dem,
      compactness: 29,
      compactness_rank: 386,
      map_bias: 81,
      turnover: 0,
      tenure: 13,
      margin: 42,
      lean: "D+26",
      neighbor_delta: -15,
      authority: "Legislature",
      shape: :bridge,
      history_summary: "D held · D held · D held · D held"
    },
    %{
      slug: "nc-09",
      label: "NC–09",
      state: "North Carolina",
      party: :rep,
      compactness: 41,
      compactness_rank: 331,
      map_bias: 77,
      turnover: 3,
      tenure: 5,
      margin: 8,
      lean: "R+7",
      neighbor_delta: -7,
      authority: "Court remedial map",
      shape: :fork,
      history_summary: "R held · D gain · R gain · R held"
    },
    %{
      slug: "pa-07",
      label: "PA–07",
      state: "Pennsylvania",
      party: :rep,
      compactness: 52,
      compactness_rank: 244,
      map_bias: 43,
      turnover: 4,
      tenure: 3,
      margin: 2,
      lean: "EVEN",
      neighbor_delta: 3,
      authority: "State court",
      shape: :chip,
      history_summary: "R held · D gain · D held · R gain"
    },
    %{
      slug: "wi-03",
      label: "WI–03",
      state: "Wisconsin",
      party: :rep,
      compactness: 63,
      compactness_rank: 157,
      map_bias: 69,
      turnover: 2,
      tenure: 3,
      margin: 5,
      lean: "R+3",
      neighbor_delta: 8,
      authority: "State supreme court",
      shape: :stair,
      history_summary: "D held · D held · R gain · R held"
    },
    %{
      slug: "co-08",
      label: "CO–08",
      state: "Colorado",
      party: :dem,
      compactness: 74,
      compactness_rank: 82,
      map_bias: 21,
      turnover: 2,
      tenure: 1,
      margin: 1,
      lean: "EVEN",
      neighbor_delta: 12,
      authority: "Independent commission",
      shape: :block,
      history_summary: "New seat · D gain · R gain · D gain"
    },
    %{
      slug: "ia-02",
      label: "IA–02",
      state: "Iowa",
      party: :rep,
      compactness: 86,
      compactness_rank: 21,
      map_bias: 12,
      turnover: 5,
      tenure: 1,
      margin: 3,
      lean: "R+2",
      neighbor_delta: 19,
      authority: "Nonpartisan staff",
      shape: :plain,
      history_summary: "D held · R gain · R held · R held"
    }
  ]

  def all, do: @districts

  def get(slug), do: Enum.find(@districts, &(&1.slug == slug))

  def sort(districts \\ @districts, sort)

  def sort(districts, :compactness), do: Enum.sort_by(districts, & &1.compactness)
  def sort(districts, :map_bias), do: Enum.sort_by(districts, & &1.map_bias, :desc)
  def sort(districts, :turnover), do: Enum.sort_by(districts, & &1.turnover, :desc)
  def sort(districts, :tenure), do: Enum.sort_by(districts, & &1.tenure, :desc)

  def parse_sort("map_bias"), do: :map_bias
  def parse_sort("turnover"), do: :turnover
  def parse_sort("tenure"), do: :tenure
  def parse_sort(_sort), do: :compactness
end
