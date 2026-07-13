defmodule VNIWeb.PageController do
  use VNIWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
