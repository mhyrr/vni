defmodule VNIWeb.ShareCard.Unfurl do
  @moduledoc """
  The 1200×630 image a VNI link unfurls into on X, iMessage, and Slack.

  Built as SVG here and rasterized to PNG by `mix vni.og.cards`, because
  no crawler accepts SVG for `og:image`. Rendering happens once, ahead of
  time, from the same `shape_path` the site already draws — the district
  silhouette is the asset, and it puts the gerrymander in front of
  someone before we have said a word.

  ## No URL is printed on the card

  Every platform renders the hostname as caption chrome beneath the
  image. Printing it on the art would be redundant and, worse, would
  couple 429 committed binaries to a domain that is not chosen yet
  (`docs/deployment/fly.md`). The story card at `/commitment/:token`
  does print a URL — it draws client-side from `Endpoint.host()` and is
  therefore correct the moment `PHX_HOST` changes.

  ## The palette is duplicated on purpose

  These hex values mirror `:root` in `assets/css/app.css`. Reading that
  file at compile time would be the `SourcesLive` idiom, but the
  Dockerfile copies `assets` *after* `mix compile`, so a compile-time
  read would break the release build. `ShareCard.UnfurlTest` asserts
  every constant here still matches the stylesheet instead — same drift
  protection, no build-order coupling.
  """

  alias VNIWeb.ShareCard

  @width 1200
  @height 630

  @ink "#11110f"
  @paper "#f2efe4"
  @muted "#706d64"
  @blue "#1557ff"
  @red "#ff4438"
  @yellow "#eaff2f"
  @green "#26e88f"
  @orange "#ff8a3d"
  @green_light "#a5f3cf"
  @paper_bright "#fffdf4"

  @display ~s(font-family="Arial Black, Helvetica Neue, Arial, sans-serif" font-weight="900")
  @body ~s(font-family="Arial, Helvetica, sans-serif" font-weight="600")
  @mono ~s(font-family="SFMono-Regular, Menlo, Monaco, Consolas, monospace" font-weight="800")

  @bar_height 88
  @margin 56

  @doc "Dimensions, so the mix task and its tests agree on one source."
  def size, do: {@width, @height}

  @doc "The palette this module bakes, for the drift test to check."
  def palette do
    %{
      "--ink" => @ink,
      "--paper" => @paper,
      "--paper-bright" => @paper_bright,
      "--muted" => @muted,
      "--blue" => @blue,
      "--red" => @red,
      "--yellow" => @yellow,
      "--green" => @green,
      "--orange" => @orange,
      "--green-light" => @green_light
    }
  end

  @doc """
  A district's card: wordmark, three lines of type, and the silhouette
  filled by its compactness tone.

  The tone carries meaning rather than decoration — orange is the worst
  quartile, green the best — so the color of the shape is already an
  argument before anyone reads the type.
  """
  def district(presented) do
    %{label: label, headline: headline, fact: fact} = ShareCard.lines(presented)

    svg([
      frame(),
      wordmark(),
      text(@margin, 232, label, @display, 96, -7.2, @ink),
      headline && text(@margin, 316, headline, @display, 60, -4.5, @ink),
      fact && text(@margin, 376, fact, @body, 30, 0, @ink),
      text(@margin, 520, tagline(), @mono, 22, 2.64, @muted),
      shape(presented)
    ])
  end

  @doc """
  The card every page that is not a district unfurls into.

  Carries the homepage headline verbatim, green "YOUR" included. The
  line is the site's sharpest sentence and it is the one that has to
  survive being seen with no other context at all.
  """
  def default do
    svg([
      frame(),
      wordmark(),
      text(@margin, 168, tagline(), @mono, 22, 2.64, @muted),
      text(@margin, 282, "YOU HATE CONGRESS.", @display, 84, -6.3, @ink),
      ~s(<text x="#{@margin}" y="352" #{@display} font-size="84" ) <>
        ~s(letter-spacing="-6.3" fill="#{@ink}">YOU'LL RE-ELECT ) <>
        ~s(<tspan fill="#{@green}">YOUR</tspan></text>),
      text(@margin, 422, "PART OF IT.", @display, 84, -6.3, @ink),
      text(
        @margin,
        534,
        "Every House district, mapped and measured. Public data, open methodology.",
        @body,
        26,
        0,
        @ink
      )
    ])
  end

  ## Composition

  defp svg(parts) do
    body = parts |> Enum.reject(&is_nil/1) |> Enum.join("\n  ")

    """
    <svg xmlns="http://www.w3.org/2000/svg" width="#{@width}" height="#{@height}" \
    viewBox="0 0 #{@width} #{@height}">
      #{body}
    </svg>
    """
  end

  defp frame do
    ~s(<rect width="#{@width}" height="#{@height}" fill="#{@paper}"/>) <>
      ~s(<rect x="3" y="3" width="#{@width - 6}" height="#{@height - 6}" ) <>
      ~s(fill="none" stroke="#{@ink}" stroke-width="6"/>)
  end

  # VOTE / NO / INCUMBENTS as three filled blocks, the site header's
  # lockup at card scale. Block widths are measured rather than flowed:
  # SVG has no box model, so the text is placed against known geometry.
  defp wordmark do
    vote_w = 195
    no_w = 135
    baseline = 60

    [
      ~s(<rect width="#{@width}" height="#{@bar_height}" fill="#{@ink}"/>),
      ~s(<rect width="#{vote_w}" height="#{@bar_height}" fill="#{@blue}"/>),
      ~s(<rect x="#{vote_w}" width="#{no_w}" height="#{@bar_height}" fill="#{@yellow}"/>),
      ~s(<rect x="#{vote_w + no_w}" width="#{@width - vote_w - no_w}" ) <>
        ~s(height="#{@bar_height}" fill="#{@red}"/>),
      text(36, baseline, "VOTE", @display, 44, -0.88, "#ffffff"),
      text(vote_w + 36, baseline, "NO", @display, 44, -0.88, @ink),
      text(vote_w + no_w + 36, baseline, "INCUMBENTS", @display, 44, -0.88, "#ffffff")
    ]
    |> Enum.join()
  end

  # The silhouette, drawn from the presenter's 0–100 normalized path.
  # Stroke width is divided by the scale because `vector-effect` support
  # in librsvg is not something to bet 429 images on.
  defp shape(%{shape_path: path} = presented) do
    box = 440
    scale = box / 100
    x = @width - @margin - box
    y = 118

    d = escape(path)

    ~s|<g transform="translate(#{x} #{y}) scale(#{scale})">| <>
      ~s|<path d="#{d}" fill-rule="evenodd" fill="#{tone(presented[:tone])}"/>| <>
      ~s|<path d="#{d}" fill-rule="evenodd" fill="none" stroke="#{@ink}" | <>
      ~s|stroke-width="#{Float.round(4 / scale, 3)}" stroke-linejoin="round"/></g>|
  end

  defp text(x, y, content, font, size, spacing, fill) do
    ~s(<text x="#{x}" y="#{y}" #{font} font-size="#{size}" ) <>
      ~s(letter-spacing="#{spacing}" fill="#{fill}">#{escape(content)}</text>)
  end

  defp tagline, do: "A NONPARTISAN ARGUMENT AGAINST PERMANENT POWER"

  # Mirrors PublicComponents.tone_fill/1 — the compactness ramp, which is
  # party-free by design. Red and blue stay reserved for party evidence.
  defp tone(:worst), do: @orange
  defp tone(:low), do: @yellow
  defp tone(:mid), do: @green_light
  defp tone(:best), do: @green
  defp tone(_unscored), do: @paper_bright

  defp escape(text) do
    text
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
end
