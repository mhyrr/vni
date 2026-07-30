defmodule Mix.Tasks.Vni.Og.Cards do
  @shortdoc "Render the unfurl images VNI links need to stop being bare URLs"

  @moduledoc """
  Rasterizes one card per current district, plus the site-wide default.

      mix vni.og.cards               # default.png + every current district
      mix vni.og.cards --slug oh-9   # one district, while iterating on the art
      mix vni.og.cards --dir DIR     # write somewhere else

  Output lands in `priv/static/images/og/`. `images` is already in
  `VNIWeb.static_paths/0`, so nothing in the endpoint changes, and the
  Dockerfile's `COPY priv priv` ships whatever is committed.

  **Commit the result.** Generation needs the database and the Docker
  build cannot reach it, so these PNGs travel as committed binaries the
  way `priv/promotion` does. Running this without committing changes
  nothing about what production serves.

  Rerun after any ingest that moves district geometry, incumbents, or
  margins — the art states facts that were true of the map it was drawn
  against, the same rule the ZIP crosswalk carries.

  ## Requirements

  `rsvg-convert` (brew `librsvg`, Debian `librsvg2-bin`), a dev-side tool
  in the same posture as GDAL's `ogr2ogr` for shapefile ingest.

  Type is baked once here rather than on a viewer's device, so the task
  refuses to run when fontconfig cannot resolve Arial Black. A silent
  substitution would produce hundreds of wrong binaries whose only
  symptom is appearing wrong in someone else's timeline.
  """

  use Mix.Task

  alias VNI.Atlas
  alias VNIWeb.{DistrictPresenter, ShareCard}

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    Logger.configure(level: :warning)

    {opts, _, invalid} = OptionParser.parse(args, strict: [slug: :string, dir: :string])
    if invalid != [], do: Mix.raise("invalid options: #{inspect(invalid)}")

    ensure_rasterizer!()
    ensure_font!()

    dir = opts[:dir] || Path.join(File.cwd!(), "priv/static/images/og")
    File.mkdir_p!(Path.join(dir, "districts"))

    written =
      case opts[:slug] do
        nil ->
          [write_default(dir) | write_districts(dir, Atlas.list_current_districts())]

        slug ->
          district = Atlas.get_district_by_slug(slug) || Mix.raise("no district #{slug}")
          write_districts(dir, [district])
      end

    Mix.shell().info("\n#{length(written)} cards, #{kb(written)} in #{relative(dir)}")
    Mix.shell().info("Commit these — the image ships what is in the repo.")
  end

  defp write_default(dir) do
    path = Path.join(dir, "default.png")
    rasterize!(ShareCard.Unfurl.default(), path)
    Mix.shell().info("default.png")
    path
  end

  defp write_districts(dir, districts) do
    districts
    |> DistrictPresenter.present_field()
    |> Task.async_stream(
      fn presented ->
        path = Path.join([dir, "districts", "#{presented.slug}.png"])
        rasterize!(ShareCard.Unfurl.district(presented), path)
        path
      end,
      max_concurrency: System.schedulers_online(),
      timeout: :infinity
    )
    |> Enum.map(fn {:ok, path} -> path end)
    |> tap(&Mix.shell().info("#{length(&1)} district cards"))
  end

  defp rasterize!(svg, png_path) do
    {width, height} = ShareCard.Unfurl.size()
    svg_path = png_path <> ".svg"
    File.write!(svg_path, svg)

    try do
      case System.cmd(
             "rsvg-convert",
             ["-w", "#{width}", "-h", "#{height}", "-o", png_path, svg_path],
             stderr_to_stdout: true
           ) do
        {_out, 0} -> :ok
        {out, code} -> Mix.raise("rsvg-convert failed (#{code}) on #{png_path}:\n#{out}")
      end
    after
      File.rm(svg_path)
    end
  end

  defp ensure_rasterizer! do
    unless System.find_executable("rsvg-convert") do
      Mix.raise("""
      rsvg-convert not found.

          brew install librsvg          # macOS
          apt-get install librsvg2-bin  # Debian
      """)
    end
  end

  # fc-match resolves what the rasterizer will actually draw with. When
  # it is missing there is nothing to check against, which is a weaker
  # position than a mismatch but not a reason to refuse.
  defp ensure_font! do
    case System.find_executable("fc-match") do
      nil ->
        Mix.shell().info("fc-match not found — cannot verify Arial Black is what gets drawn.")

      _found ->
        {family, 0} = System.cmd("fc-match", ["--format=%{family}", "Arial Black"])

        unless String.contains?(family, "Arial Black") do
          Mix.raise("""
          fontconfig resolves "Arial Black" to "#{family}".

          Every card would bake that substitution, and the only symptom is
          the art looking wrong in someone else's timeline. Install Arial
          Black, or run this on a machine that has it.
          """)
        end
    end
  end

  defp relative(path), do: Path.relative_to(path, File.cwd!())

  defp kb(paths) do
    bytes = paths |> Enum.map(&File.stat!(&1).size) |> Enum.sum()
    "#{Float.round(bytes / 1024 / 1024, 1)} MB"
  end
end
