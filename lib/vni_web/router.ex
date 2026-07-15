defmodule VNIWeb.Router do
  use VNIWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {VNIWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", VNIWeb do
    pipe_through :browser

    live_session :public do
      live "/", HomeLive, :index
      live "/atlas", AtlasLive, :index
      live "/districts", DistrictLive.Index, :index
      live "/districts/:slug", DistrictLive.Show, :show
      live "/states", StateLive.Index, :index
      live "/states/:state", StateLive.Show, :show
      live "/methodology", MethodologyLive, :index
      live "/sources", SourcesLive, :index
      live "/act", ActionLive, :index
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", VNIWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:vni, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: VNIWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
