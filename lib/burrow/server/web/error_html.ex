defmodule Burrow.Server.Web.ErrorHTML do
  @moduledoc """
  Simple error HTML renderer for the request inspector.
  """

  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
