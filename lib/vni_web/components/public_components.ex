defmodule VNIWeb.PublicComponents do
  @moduledoc "Public-facing interface components for VNI."

  use Phoenix.Component

  attr(:path, :string, required: true)
  attr(:tone, :atom, default: :yellow)
  attr(:fill_opacity, :float, default: nil)
  attr(:class, :string, default: nil)

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

  attr(:id, :string, required: true)
  attr(:context, :map, required: true)
  attr(:tone, :atom, default: :neutral)
  attr(:class, :string, default: nil)

  @doc """
  The district in its state: opens framed on the district, then pulls out to the
  whole state with the siblings it was drawn alongside.

  Both boxes come from `DistrictPresenter.state_context/2` in one shared frame,
  so the pull-out is a viewBox tween — nothing moves, the window widens. At-large
  districts have no siblings and render static.
  """
  def district_context_map(assigns) do
    ~H"""
    <svg
      id={@id}
      viewBox={@context.focus_box}
      data-frame={@context.view_box}
      data-focus={@context.focus_box}
      data-animate={to_string(@context.animate?)}
      phx-hook=".StateZoom"
      phx-update="ignore"
      aria-hidden="true"
      class={@class}
    >
      <g class="district-siblings" opacity={if @context.animate?, do: "0", else: "1"}>
        <path
          :for={path <- @context.sibling_paths}
          d={path}
          fill-rule="evenodd"
          fill="none"
          stroke="currentColor"
          stroke-width="1"
          stroke-opacity="0.45"
          vector-effect="non-scaling-stroke"
        />
      </g>
      <path
        :if={@context.animate?}
        class="district-halo"
        d={@context.subject_path}
        fill-rule="evenodd"
        fill="none"
        stroke="var(--paper-bright)"
        stroke-width="7"
        stroke-linejoin="round"
        vector-effect="non-scaling-stroke"
        opacity="0"
      />
      <path d={@context.subject_path} fill-rule="evenodd" class={tone_fill(@tone)} />
      <path
        d={@context.subject_path}
        fill-rule="evenodd"
        fill="none"
        stroke="currentColor"
        stroke-width="2.25"
        vector-effect="non-scaling-stroke"
      />
      <path
        :if={@context.reticle_path}
        class="district-reticle"
        d={@context.reticle_path}
        fill="none"
        stroke="currentColor"
        stroke-width="1.75"
        vector-effect="non-scaling-stroke"
        opacity={if @context.animate?, do: "0", else: "1"}
      />
    </svg>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".StateZoom">
      const HOLD_MS = 400
      const ZOOM_MS = 1500

      const box = (value) => value.split(" ").map(Number)
      // Ease out cubic: the pull-out decelerates into the state view.
      const ease = (t) => 1 - Math.pow(1 - t, 3)

      export default {
        mounted() {
          const siblings = this.el.querySelector(".district-siblings")
          const reticle = this.el.querySelector(".district-reticle")
          const halo = this.el.querySelector(".district-halo")
          const frame = this.el.dataset.frame
          const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches
          const reveal = (el, value) => { if (el) { el.setAttribute("opacity", value) } }

          // At-large districts have nothing to pull out to, and reduced motion
          // gets the end state directly — it carries strictly more information
          // than the isolated shape.
          if (this.el.dataset.animate !== "true" || reduced) {
            this.el.setAttribute("viewBox", frame)
            reveal(siblings, "1")
            reveal(reticle, "1")
            reveal(halo, "1")
            return
          }

          const from = box(this.el.dataset.focus)
          const to = box(frame)
          let started = null

          const step = (now) => {
            if (started === null) { started = now }
            const elapsed = now - started - HOLD_MS

            if (elapsed >= 0) {
              const progress = ease(Math.min(elapsed / ZOOM_MS, 1))

              this.el.setAttribute(
                "viewBox",
                from.map((v, i) => v + (to[i] - v) * progress).join(" ")
              )
              // Siblings arrive in the back half, once there is room for them.
              // Halo and reticle land last: an urban district shrinks to a smudge
              // among its neighbours' lines, and both exist to pull it back out.
              reveal(siblings, Math.max(0, (progress - 0.35) / 0.65).toFixed(3))
              reveal(halo, Math.max(0, (progress - 0.5) / 0.5).toFixed(3))
              reveal(reticle, Math.max(0, (progress - 0.7) / 0.3).toFixed(3))
            }

            if (elapsed < ZOOM_MS) { this.zoom = requestAnimationFrame(step) }
          }

          this.zoom = requestAnimationFrame(step)
        },

        destroyed() {
          cancelAnimationFrame(this.zoom)
        }
      }
    </script>
    """
  end

  attr(:id, :string, default: "dataset-notice")
  attr(:congress, :integer, default: 119)
  attr(:vintage, :integer, default: 2025)

  def dataset_notice(assigns) do
    ~H"""
    <div id={@id} class="preview-notice">
      <strong>
        {@congress}th Congress · U.S. Census TIGER/Line {@vintage} · methodology {VNI.Scores.methodology_version()}
      </strong>
    </div>
    """
  end

  attr(:context, :map, required: true)

  def congress_time_rail(assigns) do
    ~H"""
    <nav id="congress-time-rail" class="congress-time-rail" aria-label="Congress map history">
      <.link
        :if={@context.previous}
        navigate={@context.previous.path}
        id="congress-time-previous"
        class="congress-time-direction congress-time-previous"
      >
        <span aria-hidden="true">←</span>
        <span>
          <small>Go back in time</small>
          <strong>{@context.previous.congress}th Congress</strong>
        </span>
      </.link>
      <span :if={!@context.previous} aria-hidden="true"></span>

      <details class="congress-time-selected">
        <summary>
          <strong>{@context.congress}th Congress</strong>
          <span>{@context.years}<span :if={@context.current?}> · Current</span></span>
        </summary>
        <div class="congress-time-menu">
          <span class="data-label">Jump to Congress</span>
          <.link
            :for={term <- @context.terms}
            navigate={term.path}
            aria-current={term.selected? && "page"}
          >
            <strong>{term.congress}th</strong>
            <span>{term.years}<span :if={term.current?}> · Current</span></span>
          </.link>
        </div>
      </details>

      <.link
        :if={@context.next}
        navigate={@context.next.path}
        id="congress-time-next"
        class="congress-time-direction congress-time-next"
      >
        <span>
          <small>Go forward in time</small>
          <strong>{@context.next.congress}th Congress</strong>
        </span>
        <span aria-hidden="true">→</span>
      </.link>
      <span :if={!@context.next} aria-hidden="true"></span>
    </nav>
    """
  end

  attr(:context, :map, required: true)

  def historical_context_notice(assigns) do
    ~H"""
    <aside
      :if={!@context.current?}
      id="historical-context-notice"
      class="historical-context-notice"
    >
      <strong>Map lens · {@context.congress}th Congress</strong>
      <span>
        District lines and compactness rewind. Facts marked current-day context do not.
      </span>
    </aside>
    """
  end

  attr(:party, :atom, default: nil)
  attr(:label, :string, required: true)
  attr(:class, :string, default: nil)

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

  attr(:label, :string, required: true)
  attr(:value, :integer, required: true)
  attr(:display, :string, required: true)
  attr(:tone, :atom, default: :yellow)
  attr(:note, :string, default: nil)

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
  attr(:label, :string, required: true)
  attr(:align, :atom, default: :left, values: [:left, :right])
  slot(:inner_block, required: true)

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
