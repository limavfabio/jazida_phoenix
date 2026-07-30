defmodule JazidaPhoenixWeb.PageController do
  use JazidaPhoenixWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
