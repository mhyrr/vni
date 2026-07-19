defmodule VNIWeb.CongressTime do
  @moduledoc """
  The public time grammar for Congress-qualified Atlas routes.

  Congress is the navigation unit; district geometry remains attached to
  the state map version seated for that Congress. Unqualified routes resolve
  to the current term, while every supported term also has a fixed URL.
  """

  alias VNI.Atlas.Census

  @terms %{
    114 => %{years: "2015–2017", vintage: 2015},
    115 => %{years: "2017–2019", vintage: 2017},
    116 => %{years: "2019–2021", vintage: 2019},
    117 => %{years: "2021–2023", vintage: 2021},
    118 => %{years: "2023–2025", vintage: 2023},
    119 => %{years: "2025–2027", vintage: 2025}
  }

  # Census's state-reported change lists classify legal plan continuity.
  # Geometry equality cannot do that job: TIGER may revise coastlines and
  # other base geography without a redistricting.
  @redrawn_states %{
    114 => ["MN"],
    115 => ["FL", "MN", "NC", "VA"],
    116 => ["CO", "MN", "PA"],
    117 => ["NC"],
    118 => :all,
    119 => ["AL", "GA", "LA", "NC", "NY"]
  }

  @type surface :: :districts | :district | :states | :state

  def current_congress, do: Census.current_congress()
  def supported_congresses, do: Census.supported_congresses()

  def resolve(nil), do: {:ok, current_congress(), false}

  def resolve(value) when is_binary(value) do
    with {congress, ""} <- Integer.parse(value),
         true <- congress in supported_congresses() do
      {:ok, congress, true}
    else
      _other -> :error
    end
  end

  @doc "Build the selected term, its neighbors, and fixed links for one surface."
  def context(congress, surface, identifier \\ nil) when is_integer(congress) do
    terms =
      supported_congresses()
      |> Enum.sort()
      |> Enum.map(fn term ->
        metadata = Map.fetch!(@terms, term)

        Map.merge(metadata, %{
          congress: term,
          current?: term == current_congress(),
          selected?: term == congress,
          path: path(surface, term, identifier)
        })
      end)

    selected_index = Enum.find_index(terms, & &1.selected?)

    previous = if selected_index > 0, do: Enum.at(terms, selected_index - 1)
    next = if selected_index < length(terms) - 1, do: Enum.at(terms, selected_index + 1)

    %{
      congress: congress,
      current?: congress == current_congress(),
      years: @terms[congress].years,
      vintage: @terms[congress].vintage,
      terms: terms,
      previous: previous,
      next: next
    }
  end

  def path(:districts, congress, nil), do: "/congresses/#{congress}/districts"

  def path(:district, congress, identifier),
    do: "/congresses/#{congress}/districts/#{identifier}"

  def path(:states, congress, nil), do: "/congresses/#{congress}/states"
  def path(:state, congress, identifier), do: "/congresses/#{congress}/states/#{identifier}"

  def current_path(:districts, nil), do: "/districts"
  def current_path(:district, identifier), do: "/districts/#{identifier}"
  def current_path(:states, nil), do: "/states"
  def current_path(:state, identifier), do: "/states/#{identifier}"

  def page_path(surface, congress, identifier, qualified?) do
    if qualified?,
      do: path(surface, congress, identifier),
      else: current_path(surface, identifier)
  end

  def with_query(path, []), do: path

  def with_query(path, params) do
    path <> "?" <> URI.encode_query(params)
  end

  @doc "Describe whether a state's district lines changed from the prior Congress."
  def map_continuity(_congress, _state, true) do
    %{changed?: false, label: "At-large · no district lines drawn"}
  end

  def map_continuity(congress, state, false) when is_integer(congress) do
    changed_states = Map.fetch!(@redrawn_states, congress)
    changed? = changed_states == :all || String.upcase(state) in changed_states

    label =
      cond do
        congress == 118 -> "Redrawn after the 2020 Census"
        changed? -> "Redrawn for the #{congress}th Congress"
        true -> "Same district lines as the #{congress - 1}th Congress"
      end

    %{changed?: changed?, label: label}
  end
end
