defmodule VNIWeb.PublicComponents do
  @moduledoc "Public-facing interface components for VNI."

  use Phoenix.Component

  attr :variant, :atom, required: true
  attr :party, :atom, default: :neutral
  attr :class, :string, default: nil

  def district_shape(assigns) do
    path =
      case assigns.variant do
        :coil -> "M14 14h58l10 12-8 11 12 15-19 20-18-9-13 10-18-15 12-17-10-12Z"
        :ribbon -> "M8 20 32 8l18 18 36-12 8 18-25 11 18 19-13 18-27-22-30 16-9-17 25-17Z"
        :bridge -> "M9 15h29l8 21 17-12 31 5-2 19-28 3-12 35-19-4 4-31-24-8Z"
        :fork -> "M10 12h30l12 24 14-18 20 9-10 23 17 24-25 3-12-24-20 16-17-13 14-16Z"
        :chip -> "M16 11h53l18 17-9 20 13 20-24 19-18-11-26 9-13-25 14-19Z"
        :stair -> "M12 12h26v14h19v15h25v17H67v28H42V69H20V47H9Z"
        :block -> "M17 10h63l13 24-11 49-52 5-20-31Z"
        :plain -> "M14 17 72 8l19 35-13 40-54 5L8 54Z"
      end

    assigns = assign(assigns, :path, path)

    ~H"""
    <svg viewBox="0 0 100 100" aria-hidden="true" class={@class}>
      <path d={@path} class={party_fill(@party)} />
      <path
        d={@path}
        fill="none"
        stroke="currentColor"
        stroke-width="2.25"
        vector-effect="non-scaling-stroke"
      />
    </svg>
    """
  end

  attr :id, :string, default: "preview-notice"

  def preview_notice(assigns) do
    ~H"""
    <div id={@id} class="preview-notice">
      <span>Interface prototype</span>
      <strong>Values are illustrative. Published scores arrive with sourced data.</strong>
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

  def party_fill(:dem), do: "fill-[var(--blue)]"
  def party_fill(:rep), do: "fill-[var(--red)]"
  def party_fill(_party), do: "fill-[var(--yellow)]"

  def party_bg(:dem), do: "bg-[var(--blue)] text-white"
  def party_bg(:rep), do: "bg-[var(--red)] text-[var(--ink)]"
  def party_bg(_party), do: "bg-[var(--yellow)] text-[var(--ink)]"

  def party_name(:dem), do: "Democratic-held"
  def party_name(:rep), do: "Republican-held"
  def party_name(_party), do: "Independent-held"

  def metric_fill(:blue), do: "bg-[var(--blue)]"
  def metric_fill(:red), do: "bg-[var(--red)]"
  def metric_fill(:green), do: "bg-[var(--green)]"
  def metric_fill(_tone), do: "bg-[var(--yellow)]"
end
