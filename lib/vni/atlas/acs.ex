defmodule VNI.Atlas.ACS do
  @moduledoc """
  Per-district population from the Census ACS 5-year API.

  Total population is B01003_001E; voting-age population is the sum of
  B05003_008E + B05003_019E (male/female 18 years and over). The ACS
  `congressional district` geography aligns to a specific Congress per
  vintage, so the vintage and the exact request URL (minus the key) are
  recorded on every row.

  The data API requires a free key (https://api.census.gov/data/key_signup.html),
  read from `CENSUS_API_KEY`. Metadata endpoints don't need one.
  """

  require Logger

  alias VNI.Atlas
  alias VNI.Atlas.{Census, District}
  alias VNI.Politics

  @default_vintage 2024
  @total_population "B01003_001E"
  @male_18_plus "B05003_008E"
  @female_18_plus "B05003_019E"
  @variables [@total_population, @male_18_plus, @female_18_plus]

  def default_vintage, do: @default_vintage

  @doc "The citation stored per row: the exact data request, without the key."
  def source_url(vintage \\ @default_vintage) do
    "https://api.census.gov/data/#{vintage}/acs/acs5" <>
      "?get=NAME,#{Enum.join(@variables, ",")}" <>
      "&for=congressional%20district:*&in=state:*"
  end

  @doc """
  Fetch (or accept `:rows` for tests — the raw API response including the
  header row) and upsert population fields per current district. Rerunnable.

  Returns `%{ingested: n, skipped: n, missing_districts: [slug]}`. Skipped
  rows are geographies outside the 435-seat map: DC, Puerto Rico, and the
  delegate district codes 98/ZZ.
  """
  def ingest!(opts \\ []) do
    vintage = Keyword.get(opts, :vintage, @default_vintage)
    [header | rows] = Keyword.get_lazy(opts, :rows, fn -> fetch!(vintage, api_key!(opts)) end)
    columns = Enum.with_index(header) |> Map.new()
    state_codes = Map.new(Census.current_manifest(), &{&1.fips, &1.code})
    citation = source_url(vintage)

    results =
      Enum.map(rows, fn row ->
        state = state_codes[Enum.at(row, columns["state"])]
        number = district_number(Enum.at(row, columns["congressional district"]))

        with true <- is_binary(state) and is_integer(number),
             slug = District.build_slug(state, number),
             %District{} = district <- Atlas.get_district_by_slug(slug) do
          {:ok, _profile} =
            Politics.upsert_profile(district, %{
              population: integer_at(row, columns, @total_population),
              voting_age_population:
                integer_at(row, columns, @male_18_plus) +
                  integer_at(row, columns, @female_18_plus),
              acs_vintage: vintage,
              population_source_url: citation
            })

          :ok
        else
          false ->
            :skipped

          nil ->
            slug = District.build_slug(state, number)
            Logger.warning("no current district for ACS geography #{slug}")
            {:missing, slug}
        end
      end)

    %{
      ingested: Enum.count(results, &(&1 == :ok)),
      skipped: Enum.count(results, &(&1 == :skipped)),
      missing_districts: for({:missing, slug} <- results, do: slug)
    }
  end

  # "00" is at-large (our number 0); 98 and ZZ are delegate/undefined codes.
  defp district_number("ZZ"), do: nil
  defp district_number("98"), do: nil
  defp district_number(code) when is_binary(code), do: String.to_integer(code)
  defp district_number(_code), do: nil

  defp integer_at(row, columns, variable) do
    row |> Enum.at(columns[variable]) |> String.to_integer()
  end

  defp fetch!(vintage, key) do
    response =
      Req.get!("https://api.census.gov/data/#{vintage}/acs/acs5",
        params: [
          get: "NAME,#{Enum.join(@variables, ",")}",
          for: "congressional district:*",
          in: "state:*",
          key: key
        ],
        redirect: false,
        receive_timeout: 120_000
      )

    with 200 <- response.status,
         rows when is_list(rows) <- response.body do
      rows
    else
      _ ->
        raise "ACS request failed (HTTP #{response.status}) — " <>
                "is CENSUS_API_KEY valid? #{source_url(vintage)}"
    end
  end

  defp api_key!(opts) do
    opts[:key] || System.get_env("CENSUS_API_KEY") ||
      raise """
      The Census data API requires a key. Get a free one at
      https://api.census.gov/data/key_signup.html and export CENSUS_API_KEY.
      """
  end
end
