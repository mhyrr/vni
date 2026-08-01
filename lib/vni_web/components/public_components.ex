defmodule VNIWeb.PublicComponents do
  @moduledoc "Public-facing interface components for VNI."

  use Phoenix.Component
  use VNIWeb, :verified_routes

  attr(:seat, :map, default: nil)
  attr(:from_zip, :boolean, default: false)
  attr(:delay_ms, :integer, default: 5_000)
  attr(:quiet_ms, :integer, default: 86_400_000)

  @doc """
  The ask, as a modal, after the reader has had a moment on the page.

  Design 004 §1 ruled a modal out on the grounds that one firing before
  the reader has read a word is the newsletter-popup pattern. Greg's call
  (2026-07-26) is that the count buried at the foot of a district page
  was not getting asked at all, and signing people up is the point. The
  difference from the pattern the spec rejected lives in the suppression,
  not the delay: it never fires where a skeptic is checking our work
  (`/methodology`, `/sources`), never inside the flow it is trying to
  start, never again once someone has committed, and it stays quiet for a
  day after any dismissal.

  ## Except when the reader arrived by ZIP

  The day of quiet is the right answer to an ask the reader did not
  invite. It is the wrong answer to one they did: typing a ZIP is asking
  which seat is yours, and this dialog is the answer. Suppressing it
  because of a *Not now* clicked on the atlas this morning spends an
  answer against a question that was never asked. So `from_zip` skips
  the quiet window — and only that check. Someone who has committed is
  still never asked again, which is the condition that matters (Greg,
  2026-08-01).

  On a district page it asks about that seat, by name, with the live
  count. Anywhere else there is no seat to name yet, so the ask is
  general and the ZIP is the route to answering it.

  Crawlers get nothing: a `<dialog>` is `display: none` until JavaScript
  opens it, and nothing here opens it on the server.
  """
  def commitment_prompt(assigns) do
    ~H"""
    <dialog
      id="commitment-prompt"
      class="commitment-prompt"
      phx-hook=".CommitmentPrompt"
      data-delay={@delay_ms}
      data-quiet={@quiet_ms}
      data-from-zip={@from_zip && "true"}
      aria-labelledby="commitment-prompt-heading"
    >
      <div class="commitment-prompt-body">
        <p :if={@seat} class="data-label">
          {if @seat.commitment_count == 0,
            do: "Nobody in #{@seat.label} has answered yet",
            else: "#{@seat.commitment_count_label} committed in #{@seat.label}"}
        </p>
        <p :if={!@seat} class="data-label">435 seats. One of them is yours.</p>

        <h2 id="commitment-prompt-heading" class="display-md mt-6">
          <span :if={@seat}>
            Will you vote against {@seat.incumbent_name || "this incumbent"} in November,
            whoever runs?
          </span>
          <span :if={!@seat}>
            Will you vote against your incumbent in November, whoever runs?
          </span>
        </h2>

        <p :if={@seat && @seat.incumbent_since} class="mt-6 text-sm leading-6">
          {@seat.incumbent_name} has held this seat since {@seat.incumbent_since}.
        </p>
        <p :if={!@seat} class="mt-6 text-sm leading-6">
          You answer it on your own district's page. Start with your ZIP.
        </p>

        <div :if={@seat} class="mt-9 flex flex-wrap items-center gap-5">
          <.link navigate={~p"/districts/#{@seat.slug}/join"} class="paper-button">
            Commit <span aria-hidden="true">→</span>
          </.link>
          <form method="dialog">
            <button type="submit" class="commitment-prompt-dismiss">Not now</button>
          </form>
        </div>

        <form :if={!@seat} action={~p"/find"} method="get" class="mt-9">
          <label for="prompt-zip" class="sr-only">Your ZIP code</label>
          <div class="flex flex-wrap items-stretch gap-3">
            <input
              type="text"
              id="prompt-zip"
              name="zip"
              inputmode="numeric"
              autocomplete="postal-code"
              maxlength="10"
              placeholder="43604"
              class="w-40 border-2 border-[var(--ink)] bg-[var(--paper-bright)] p-3 font-mono text-xl font-bold tracking-widest"
            />
            <button type="submit" class="paper-button">
              Find my seat <span aria-hidden="true">→</span>
            </button>
          </div>
        </form>

        <form :if={!@seat} method="dialog" class="mt-6">
          <button type="submit" class="commitment-prompt-dismiss">Not now</button>
        </form>

        <p class="mt-8 text-xs leading-5">
          We publish how many people committed in each district. We never publish who they are.
        </p>
      </div>
    </dialog>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".CommitmentPrompt">
      const DISMISSED_AT = "vni:prompt-dismissed-at"
      const COMMITTED = "vni:committed"

      // Private-mode Safari throws on access rather than returning null.
      const store = () => { try { return window.localStorage } catch (_) { return null } }

      export default {
        mounted() {
          // Arriving by ZIP is the reader asking the question this dialog
          // answers, so a `Not now` from somewhere else does not spend the
          // answer. Consumed on arrival: the marker leaves the URL so a
          // reload — or a shared link — is an ordinary visit again.
          const fromZip = this.el.dataset.fromZip === "true"
          if (fromZip) {
            const url = new URL(window.location)
            if (url.searchParams.has("from")) {
              url.searchParams.delete("from")
              // Keep LiveView's own history state; only the URL changes.
              window.history.replaceState(window.history.state, "", url)
            }
          }

          const memory = store()
          if (!memory) { return }

          // Someone who has committed is never asked again. This one holds
          // even for a ZIP arrival — they already answered.
          if (memory.getItem(COMMITTED)) { return }

          const dismissedAt = Number(memory.getItem(DISMISSED_AT) || 0)
          const quiet = Number(this.el.dataset.quiet)
          if (!fromZip && dismissedAt && Date.now() - dismissedAt < quiet) { return }

          this.timer = window.setTimeout(() => {
            if (this.el.isConnected && !this.el.open) { this.el.showModal() }
          }, Number(this.el.dataset.delay))

          // Every route out of the dialog is a dismissal: the button, Escape,
          // and the backdrop all fire `close`, and all of them mean not now.
          this.onClose = () => {
            const memory = store()
            if (memory) { memory.setItem(DISMISSED_AT, String(Date.now())) }
          }

          this.onClick = (event) => {
            if (event.target === this.el) { this.el.close() }
          }

          this.el.addEventListener("close", this.onClose)
          this.el.addEventListener("click", this.onClick)
        },

        destroyed() {
          window.clearTimeout(this.timer)
          this.el.removeEventListener("close", this.onClose)
          this.el.removeEventListener("click", this.onClick)
        }
      }
    </script>
    """
  end

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
