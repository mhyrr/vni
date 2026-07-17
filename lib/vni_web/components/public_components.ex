defmodule VNIWeb.PublicComponents do
  @moduledoc "Public-facing interface components for VNI."

  use Phoenix.Component

  attr :path, :string, required: true
  attr :tone, :atom, default: :yellow
  attr :fill_opacity, :float, default: nil
  attr :class, :string, default: nil

  def district_shape(assigns) do
    ~H"""
    <svg viewBox="0 0 100 100" aria-hidden="true" class={@class}>
      <path d={@path} fill-rule="evenodd" class={tone_fill(@tone)} fill-opacity={@fill_opacity} />
      <path
        d={@path}
        fill-rule="evenodd"
        fill="none"
        stroke="currentColor"
        stroke-width="2.25"
        vector-effect="non-scaling-stroke"
      />
    </svg>
    """
  end

  attr :id, :string, default: "dataset-notice"

  def dataset_notice(assigns) do
    ~H"""
    <div id={@id} class="preview-notice">
      <strong>
        119th Congress · U.S. Census TIGER/Line 2025 · methodology {VNI.Scores.methodology_version()}
      </strong>
    </div>
    """
  end

  attr :party, :atom, default: nil
  attr :label, :string, required: true
  attr :class, :string, default: nil

  @doc """
  A party marker in evidence colors: blue for D, red for R, outlined for
  anything else. Raw record data only — the color states the party, it
  never grades the officeholder.
  """
  def party_mark(assigns) do
    ~H"""
    <span class={["px-2 py-1 data-label", party_chip(@party), @class]}>{@label}</span>
    """
  end

  defp party_chip(:dem), do: "bg-[var(--blue)] text-white"
  defp party_chip(:rep), do: "bg-[var(--red)] text-[var(--ink)]"
  defp party_chip(_party), do: "border-2 border-[var(--ink)]"

  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :display, :string, required: true
  attr :tone, :atom, default: :yellow
  attr :note, :string, default: nil

  def metric_bar(assigns) do
    ~H"""
    <div class="metric-bar">
      <div class="flex items-end justify-between gap-4">
        <span class="data-label">{@label}</span>
        <strong class="font-mono text-sm">{@display}</strong>
      </div>
      <div class="metric-track" aria-hidden="true">
        <span class={metric_fill(@tone)} style={"width: #{@value}%"}></span>
      </div>
      <p :if={@note} class="mt-2 text-xs text-[var(--muted)]">{@note}</p>
    </div>
    """
  end

  # :red / :blue are bold party evidence colors (lean mode) — never
  # compactness. Compactness runs the diverging :worst → :best ramp:
  # orange → yellow → light green → green.
  def tone_fill(:blue), do: "fill-[var(--blue)]"
  def tone_fill(:red), do: "fill-[var(--red)]"
  def tone_fill(:green), do: "fill-[var(--green)]"
  def tone_fill(:neutral), do: "fill-[var(--paper-bright)]"
  def tone_fill(:worst), do: "fill-[var(--orange)]"
  def tone_fill(:low), do: "fill-[var(--yellow)]"
  def tone_fill(:mid), do: "fill-[var(--green-light)]"
  def tone_fill(:best), do: "fill-[var(--green)]"
  def tone_fill(_tone), do: "fill-[var(--yellow)]"

  def tone_bg(:blue), do: "bg-[var(--blue)] text-white"
  def tone_bg(:red), do: "bg-[var(--red)] text-[var(--ink)]"
  def tone_bg(:green), do: "bg-[var(--green)] text-[var(--ink)]"
  def tone_bg(:neutral), do: "bg-[var(--paper-bright)] text-[var(--ink)]"
  def tone_bg(:worst), do: "bg-[var(--orange)] text-[var(--ink)]"
  def tone_bg(:low), do: "bg-[var(--yellow)] text-[var(--ink)]"
  def tone_bg(:mid), do: "bg-[var(--green-light)] text-[var(--ink)]"
  def tone_bg(:best), do: "bg-[var(--green)] text-[var(--ink)]"
  def tone_bg(_tone), do: "bg-[var(--yellow)] text-[var(--ink)]"

  def metric_fill(:blue), do: "bg-[var(--blue)]"
  def metric_fill(:red), do: "bg-[var(--red)]"
  def metric_fill(:green), do: "bg-[var(--green)]"
  def metric_fill(:worst), do: "bg-[var(--orange)]"
  def metric_fill(:low), do: "bg-[var(--yellow)]"
  def metric_fill(:mid), do: "bg-[var(--green-light)]"
  def metric_fill(:best), do: "bg-[var(--green)]"
  def metric_fill(_tone), do: "bg-[var(--yellow)]"

  @doc """
  Column-header label carrying a themed hover/focus tooltip that explains
  the metric in place. Keyboard-reachable via tabindex.
  """
  attr :label, :string, required: true
  attr :align, :atom, default: :left, values: [:left, :right]
  slot :inner_block, required: true

  def metric_header(assigns) do
    ~H"""
    <span class="metric-tip" tabindex="0">
      <span class="data-label metric-tip-label">{@label}</span>
      <span
        class={["metric-tip-panel", @align == :right && "metric-tip-panel-right"]}
        role="tooltip"
      >
        {render_slot(@inner_block)}
      </span>
    </span>
    """
  end
end
