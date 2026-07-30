defmodule VNIWeb.ShareCard.UnfurlTest do
  @moduledoc """
  The unfurl art, checked without a rasterizer.

  Rendering PNGs in CI would buy a toolchain dependency and prove
  nothing the SVG does not already say, so the rasterize is exercised by
  running the task. What is worth asserting here is that the card states
  the district's facts and that its baked palette still matches the
  stylesheet it was copied from.
  """

  use ExUnit.Case, async: true

  alias VNIWeb.ShareCard.Unfurl

  @stylesheet Path.join([__DIR__, "..", "..", "..", "assets", "css", "app.css"])

  defp district(overrides \\ %{}) do
    Map.merge(
      %{
        slug: "oh-9",
        label: "OH-09",
        shape_path: "M10 10L90 10L90 90L10 90Z",
        tone: :worst,
        incumbent_tenure: 43,
        commitment_goal_basis: :margin,
        last_margin_votes: "2,382",
        last_margin_cycle: 2024,
        national_rank: 412,
        ranked_total: 429
      },
      overrides
    )
  end

  # What a viewer actually reads: text node contents, not the markup
  # around them. The document itself always carries the SVG namespace
  # URL, which is not a URL anyone sees.
  defp visible_text(svg) do
    ~r|>([^<>]+)<|
    |> Regex.scan(svg, capture: :all_but_first)
    |> List.flatten()
    |> Enum.join(" ")
  end

  defp shape_fill(svg) do
    ~r|<g transform=[^>]*><path [^>]*fill="(#[0-9a-f]{6})"|
    |> Regex.run(svg, capture: :all_but_first)
    |> hd()
  end

  describe "palette" do
    test "every baked color still matches :root in app.css" do
      css = File.read!(@stylesheet)

      root =
        Regex.run(~r/:root\s*\{(.*?)\}/s, css, capture: :all_but_first)
        |> hd()

      declared =
        Regex.scan(~r/(--[a-z-]+):\s*(#[0-9a-fA-F]{3,8})\s*;/, root, capture: :all_but_first)
        |> Map.new(fn [name, hex] -> {name, String.downcase(hex)} end)

      for {name, baked} <- Unfurl.palette() do
        assert declared[name] == String.downcase(baked),
               "#{name} is #{inspect(baked)} in Unfurl and #{inspect(declared[name])} in app.css"
      end
    end
  end

  describe "district/1" do
    test "states the seat, the tenure, and the margin" do
      svg = Unfurl.district(district())

      assert svg =~ "OH-09"
      assert svg =~ "HELD 43 YEARS"
      assert svg =~ "Decided by 2,382 votes in 2024."
    end

    test "carries the wordmark and the nonpartisan line" do
      svg = Unfurl.district(district())

      assert svg =~ ">VOTE<"
      assert svg =~ ">NO<"
      assert svg =~ ">INCUMBENTS<"
      assert svg =~ "A NONPARTISAN ARGUMENT AGAINST PERMANENT POWER"
    end

    test "prints no URL — the platform's caption chrome already shows the host" do
      text = visible_text(Unfurl.district(district()))

      refute text =~ ~r"https?://"
      refute text =~ ~r"\.(org|dev|com)\b"
    end

    test "never names the incumbent" do
      svg = Unfurl.district(district(%{incumbent_name: "Marcy Kaptur"}))

      refute svg =~ "Kaptur"
    end

    test "fills the silhouette from the compactness ramp, not the party colors" do
      assert shape_fill(Unfurl.district(district(%{tone: :worst}))) == "#ff8a3d"
      assert shape_fill(Unfurl.district(district(%{tone: :best}))) == "#26e88f"
      assert shape_fill(Unfurl.district(district(%{tone: :low}))) == "#eaff2f"

      # Party red and blue appear in the wordmark and nowhere else.
      refute shape_fill(Unfurl.district(district(%{tone: :worst}))) in ["#1557ff", "#ff4438"]
    end

    test "omits lines it has no facts for rather than drawing empty type" do
      svg =
        Unfurl.district(
          district(%{
            incumbent_tenure: nil,
            commitment_goal_basis: :unknown,
            national_rank: nil,
            ranked_total: nil
          })
        )

      assert svg =~ "OH-09"
      refute svg =~ "HELD"
      refute svg =~ "RANK"
    end

    test "renders the district's own geometry" do
      svg = Unfurl.district(district(%{shape_path: "M1 2L3 4Z"}))

      assert svg =~ ~s|d="M1 2L3 4Z"|
    end

    test "declares the dimensions the task rasterizes at" do
      {width, height} = Unfurl.size()
      svg = Unfurl.district(district())

      assert svg =~ ~s|width="#{width}"|
      assert svg =~ ~s|height="#{height}"|
      assert {1200, 630} == {width, height}
    end
  end

  describe "default/0" do
    test "carries the homepage headline, green YOUR included" do
      svg = Unfurl.default()

      assert svg =~ "YOU HATE CONGRESS."
      assert svg =~ "YOU'LL RE-ELECT"
      assert svg =~ ~s|<tspan fill="#26e88f">YOUR</tspan>|
      assert svg =~ "PART OF IT."
    end

    test "prints no URL either" do
      refute visible_text(Unfurl.default()) =~ ~r"https?://"
    end
  end
end
