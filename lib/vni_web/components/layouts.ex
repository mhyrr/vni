defmodule VNIWeb.Layouts do
  @moduledoc "Application layouts and shared public navigation."

  use VNIWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  attr :active, :atom, default: nil

  attr :prompt, :boolean,
    default: true,
    doc: "false inside the commitment flow itself — see commitment_prompt/1"

  attr :seat, :map,
    default: nil,
    doc: "the presented district, when the page is about one seat"

  slot :inner_block, required: true

  def app(assigns) do
    # Never where a skeptic is checking our work, and never inside the
    # flow the prompt exists to start.
    assigns =
      assign(assigns, :prompt?, assigns.prompt and assigns.active not in [:methodology, :sources])

    ~H"""
    <header id="site-header" class="site-header">
      <.link navigate={~p"/"} class="wordmark" aria-label="Vote No Incumbents home">
        <span class="wordmark-vote">VOTE</span>
        <span class="wordmark-no">NO</span>
        <span class="wordmark-incumbents">INCUMBENTS</span>
      </.link>

      <nav id="primary-navigation" aria-label="Primary navigation" class="primary-nav">
        <.link navigate={~p"/"} class={[@active == :home && "is-active"]}>The case</.link>
        <.link navigate={~p"/atlas"} class={[@active == :atlas && "is-active"]}>Atlas</.link>
        <.link navigate={~p"/districts"} class={[@active == :districts && "is-active"]}>
          Districts
        </.link>
        <.link navigate={~p"/states"} class={[@active == :states && "is-active"]}>
          States
        </.link>
        <.link navigate={~p"/methodology"} class={[@active == :methodology && "is-active"]}>
          Method
        </.link>
      </nav>

      <%!-- Interface 002 §5: the primary CTA is Find your district, not
      Sign up. It is absent entirely on /methodology and /sources — those
      are where a hostile reader goes to check our work, and asking there
      converts a skeptic into an ex-visitor. --%>
      <form
        :if={@active not in [:methodology, :sources]}
        id="header-find"
        action={~p"/find"}
        method="get"
        class="header-find"
      >
        <label for="header-zip" class="sr-only">Find your district by ZIP code</label>
        <input
          type="text"
          id="header-zip"
          name="zip"
          inputmode="numeric"
          autocomplete="postal-code"
          maxlength="10"
          placeholder="ZIP"
          aria-label="ZIP code"
        />
        <button type="submit">Find your seat <span aria-hidden="true">→</span></button>
      </form>
    </header>

    <main id="main-content">
      {render_slot(@inner_block)}
    </main>

    <footer id="site-footer" class="site-footer">
      <div>
        <p class="data-label">A nonpartisan argument against permanent power.</p>
        <p class="mt-3 max-w-xl font-serif text-lg leading-snug">
          No incumbents. No gerrymanders. Term limits. Leave the Supreme Court alone.
        </p>
      </div>
      <div class="grid grid-cols-2 gap-x-10 gap-y-2 text-sm font-bold uppercase tracking-wide">
        <.link navigate={~p"/atlas"}>Atlas</.link>
        <.link navigate={~p"/districts"}>Districts</.link>
        <.link navigate={~p"/states"}>States</.link>
        <.link navigate={~p"/methodology"}>Methodology</.link>
        <.link navigate={~p"/sources"}>Sources</.link>
        <.link navigate={~p"/act"}>Act</.link>
      </div>
      <p class="font-mono text-xs uppercase">
        Methodology {VNI.Scores.methodology_version()} · Prototype
      </p>
    </footer>

    <.commitment_prompt :if={@prompt?} seat={@seat} />

    <.flash_group flash={@flash} />
    """
  end

  attr :flash, :map, required: true
  attr :id, :string, default: "flash-group"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
