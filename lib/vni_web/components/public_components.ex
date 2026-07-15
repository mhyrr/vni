defmodule VNIWeb.PublicComponents do
  @moduledoc "Public-facing interface components for VNI."

  use Phoenix.Component

  attr :path, :string, required: true
  attr :tone, :atom, default: :yellow
  attr :class, :string, default: nil

  def district_shape(assigns) do
    ~H"""
    <svg viewBox="0 0 100 100" aria-hidden="true" class={@class}>
      <path d={@path} fill-rule="evenodd" class={tone_fill(@tone)} />
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

  def tone_fill(:blue), do: "fill-[var(--blue)]"
  def tone_fill(:red), do: "fill-[var(--red)]"
  def tone_fill(:green), do: "fill-[var(--green)]"
  def tone_fill(:neutral), do: "fill-[var(--paper-bright)]"
  def tone_fill(_tone), do: "fill-[var(--yellow)]"

  def tone_bg(:blue), do: "bg-[var(--blue)] text-white"
  def tone_bg(:red), do: "bg-[var(--red)] text-[var(--ink)]"
  def tone_bg(:green), do: "bg-[var(--green)] text-[var(--ink)]"
  def tone_bg(:neutral), do: "bg-[var(--paper-bright)] text-[var(--ink)]"
  def tone_bg(_tone), do: "bg-[var(--yellow)] text-[var(--ink)]"

  def metric_fill(:blue), do: "bg-[var(--blue)]"
  def metric_fill(:red), do: "bg-[var(--red)]"
  def metric_fill(:green), do: "bg-[var(--green)]"
  def metric_fill(_tone), do: "bg-[var(--yellow)]"
end
