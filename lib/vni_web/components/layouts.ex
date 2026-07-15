defmodule VNIWeb.Layouts do
  @moduledoc "Application layouts and shared public navigation."

  use VNIWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  attr :active, :atom, default: nil
  slot :inner_block, required: true

  def app(assigns) do
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
        <.link navigate={~p"/methodology"} class={[@active == :methodology && "is-active"]}>
          Method
        </.link>
      </nav>

      <.link navigate={~p"/act"} id="header-action" class="header-action">
        Cross the line <span aria-hidden="true">↗</span>
      </.link>
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
        <.link navigate={~p"/methodology"}>Methodology</.link>
        <.link navigate={~p"/act"}>Act</.link>
      </div>
      <p class="font-mono text-xs uppercase">
        Methodology {VNI.Scores.methodology_version()} · Prototype
      </p>
    </footer>

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
