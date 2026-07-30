defmodule VNIWeb.SocialMeta do
  @moduledoc """
  What a VNI link looks like when it leaves the site.

  Without these tags a link unfurls as bare text everywhere it is
  pasted — X, iMessage, Slack, WhatsApp — which is most of how anything
  spreads. The tags render in the root layout, so they cover every page
  including the ones nobody thought to wire up.

  ## Why the dead render is the only one that matters

  A crawler runs no JavaScript and never opens a socket. It sees the
  HTTP response, and `mount/3` has already run by the time the root
  layout renders it — so assigns set in mount are exactly what unfurls.
  Anything assigned later, in `handle_event/3` or an async reply, is
  invisible to every platform that matters.

  ## No og:url

  Every platform falls back to the URL it fetched, VNI has no
  query-parameter variants of a page to canonicalize, and threading the
  current URI into the root layout is real plumbing for no unfurl.
  Deliberately absent rather than forgotten.
  """

  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: VNIWeb.Endpoint,
    router: VNIWeb.Router,
    statics: VNIWeb.static_paths()

  @description "See how congressional districts entrench power—and what it would " <>
                 "take to vote every incumbent out."

  attr(:page_title, :string, default: nil)
  attr(:title, :string, default: nil)
  attr(:description, :string, default: nil)
  attr(:image, :string, default: nil)

  @doc """
  The Open Graph and Twitter tags for a page.

  `twitter:card` is the one tag X needs to render a large image; the
  rest of what it shows it reads from `og:*`.
  """
  def tags(assigns) do
    assigns =
      assigns
      |> assign(:og_title, assigns.title || assigns.page_title || "Vote No Incumbents")
      |> assign(:og_description, assigns.description || @description)
      |> assign(:og_image, absolute(assigns.image || default_image()))

    ~H"""
    <meta property="og:type" content="website" />
    <meta property="og:site_name" content="Vote No Incumbents" />
    <meta property="og:title" content={@og_title} />
    <meta property="og:description" content={@og_description} />
    <meta property="og:image" content={@og_image} />
    <meta property="og:image:width" content="1200" />
    <meta property="og:image:height" content="630" />
    <meta name="twitter:card" content="summary_large_image" />
    """
  end

  @doc "The site-wide card, for every page that is not a current district."
  def default_image, do: ~p"/images/og/default.png"

  @doc """
  A district's own card — but only for districts on the current map.

  `mix vni.og.cards` renders the current field, and the facts it bakes
  are true of that map. A page under an earlier congress would otherwise
  unfurl into current tenure and current margins over a shape that has
  since been redrawn.

  Takes the slug rather than a presented district on purpose: the
  district page loads through `assign_async`, so the presented struct
  does not exist yet at the dead render, which is the only render a
  crawler ever sees.
  """
  def district_image(slug, true = _current_map?), do: ~p"/images/og/districts/#{slug <> ".png"}"
  def district_image(_slug, false = _current_map?), do: default_image()

  defp absolute("http" <> _rest = url), do: url
  defp absolute(path), do: VNIWeb.Endpoint.url() <> path
end
