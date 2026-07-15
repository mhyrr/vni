defmodule VNI.Politics.Legislators do
  @moduledoc """
  Incumbent ingestion from the public-domain `unitedstates/congress-legislators`
  dataset (community-maintained from official sources, includes bioguide ids).

  Published facts only: name, party exactly as the record states it, first
  House-term start year, bioguide id. `incumbent_since` is the year the member
  first took a House seat — tenure is arithmetic on the public record, not a
  judgment about the officeholder.
  """

  require Logger

  alias VNI.Atlas
  alias VNI.Atlas.District
  alias VNI.Politics

  @source_url "https://unitedstates.github.io/congress-legislators/legislators-current.yaml"

  # Non-voting delegates and the resident commissioner appear as `rep` terms
  # but have no district in the 435-seat map set.
  @non_voting ~w(AS DC GU MP PR VI)

  def source_url, do: @source_url

  @doc """
  Download (or accept `:yaml` for tests), parse, and upsert one profile per
  sitting House member whose current term is a voting seat. Rerunnable —
  upserts key on district identity and replace only incumbent fields.

  Returns `%{ingested: n, skipped_non_voting: n, missing_districts: [slug]}`.
  """
  def ingest_current!(opts \\ []) do
    yaml = Keyword.get_lazy(opts, :yaml, &download!/0)
    legislators = YamlElixir.read_from_string!(yaml)

    reps =
      legislators
      |> Enum.map(&{&1, current_term(&1)})
      |> Enum.filter(fn {_legislator, term} -> term["type"] == "rep" end)

    {voting, non_voting} =
      Enum.split_with(reps, fn {_legislator, term} -> term["state"] not in @non_voting end)

    results =
      Enum.map(voting, fn {legislator, term} ->
        slug = District.build_slug(term["state"], term["district"])

        case Atlas.get_district_by_slug(slug) do
          nil ->
            Logger.warning("no current district for #{slug}; skipping #{name(legislator)}")
            {:missing, slug}

          district ->
            {:ok, _profile} = Politics.upsert_profile(district, profile_attrs(legislator, term))
            :ok
        end
      end)

    %{
      ingested: Enum.count(results, &(&1 == :ok)),
      skipped_non_voting: length(non_voting),
      missing_districts: for({:missing, slug} <- results, do: slug)
    }
  end

  defp profile_attrs(legislator, term) do
    %{
      incumbent_name: name(legislator),
      incumbent_party: party(term["party"]),
      incumbent_since: first_house_year(legislator),
      bioguide_id: legislator["id"]["bioguide"],
      incumbent_source_url: @source_url
    }
  end

  # The dataset orders terms chronologically; the last one is the current
  # office for everyone in legislators-current.
  defp current_term(legislator), do: List.last(legislator["terms"])

  defp first_house_year(legislator) do
    legislator["terms"]
    |> Enum.filter(&(&1["type"] == "rep"))
    |> Enum.map(&(&1["start"] |> String.slice(0, 4) |> String.to_integer()))
    |> Enum.min()
  end

  defp name(legislator) do
    legislator["name"]["official_full"] ||
      "#{legislator["name"]["first"]} #{legislator["name"]["last"]}"
  end

  # Raw party data, mapped to the storage enum — never inferred. An unknown
  # party is a schema question, not something to coerce quietly.
  defp party("Democrat"), do: :dem
  defp party("Republican"), do: :rep
  defp party("Independent"), do: :ind
  defp party(other), do: raise(ArgumentError, "unmapped party in source data: #{inspect(other)}")

  defp download! do
    response = Req.get!(@source_url, receive_timeout: 120_000)

    if response.status != 200 do
      raise "failed to download #{@source_url} (HTTP #{response.status})"
    end

    response.body
  end
end
