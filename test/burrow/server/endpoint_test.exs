defmodule Burrow.Server.EndpointTest do
  use ExUnit.Case, async: false

  import Plug.Test
  import Plug.Conn

  alias Burrow.Server.{Dispatcher, TunnelEndpoint}

  setup do
    start_supervised!({Burrow.Server.TunnelRegistry, name: Burrow.Server.TunnelRegistry})
    start_supervised!({Burrow.Server.PendingRequests, name: Burrow.Server.PendingRequests})
    start_supervised!(Burrow.Server.Web.Endpoint)

    Application.put_env(:burrow, :server, base_domain: "burrow.test")

    :ok
  end

  describe "Dispatcher" do
    test "routes main domain requests to Web.Endpoint" do
      conn = conn(:get, "/health")
      conn = %{conn | host: "burrow.test"}
      conn = Dispatcher.call(conn, Dispatcher.init([]))

      assert conn.status == 200
      assert conn.resp_body == "ok"
    end

    test "routes subdomain requests to TunnelEndpoint" do
      conn = conn(:get, "/")
      conn = %{conn | host: "myapp.burrow.test"}
      conn = Dispatcher.call(conn, Dispatcher.init([]))

      # Should get 404 since tunnel doesn't exist
      assert conn.status == 404
    end

    test "routes localhost to main domain" do
      conn = conn(:get, "/health")
      conn = %{conn | host: "localhost"}
      conn = Dispatcher.call(conn, Dispatcher.init([]))

      assert conn.status == 200
    end

    test "routes IP address to main domain" do
      conn = conn(:get, "/health")
      conn = %{conn | host: "127.0.0.1"}
      conn = Dispatcher.call(conn, Dispatcher.init([]))

      assert conn.status == 200
    end
  end

  describe "TunnelEndpoint.extract_subdomain/1" do
    test "extracts subdomain from valid host" do
      conn = conn(:get, "/")
      conn = %{conn | host: "myapp.burrow.test"}

      assert TunnelEndpoint.extract_subdomain(conn) == {:ok, "myapp"}
    end

    test "extracts subdomain with hyphens" do
      conn = conn(:get, "/")
      conn = %{conn | host: "my-cool-app.burrow.test"}

      assert TunnelEndpoint.extract_subdomain(conn) == {:ok, "my-cool-app"}
    end

    test "returns error for base domain without subdomain" do
      conn = conn(:get, "/")
      conn = %{conn | host: "burrow.test"}

      assert TunnelEndpoint.extract_subdomain(conn) == :error
    end

    test "returns error for non-matching domain" do
      conn = conn(:get, "/")
      conn = %{conn | host: "myapp.other.com"}

      assert TunnelEndpoint.extract_subdomain(conn) == :error
    end
  end

  describe "TunnelEndpoint subdomain routing" do
    test "returns 404 for non-existent tunnel" do
      conn = conn(:get, "/")
      conn = %{conn | host: "nonexistent.burrow.test"}
      conn = TunnelEndpoint.call(conn, TunnelEndpoint.init([]))

      assert conn.status == 404
    end
  end

  describe "tunnel control endpoints" do
    test "POST /tunnel/connect with missing body returns 400" do
      conn =
        conn(:post, "/tunnel/connect", "")
        |> put_req_header("content-type", "application/json")

      conn = %{conn | host: "burrow.test"}
      conn = Dispatcher.call(conn, Dispatcher.init([]))

      assert conn.status == 400
    end

    test "POST /tunnel/connect with invalid JSON returns 400" do
      conn =
        conn(:post, "/tunnel/connect", "not json")
        |> put_req_header("content-type", "application/json")

      conn = %{conn | host: "burrow.test"}
      conn = Dispatcher.call(conn, Dispatcher.init([]))

      assert conn.status == 400
    end
  end

  describe "CORS headers" do
    test "main domain OPTIONS request returns CORS headers" do
      conn = conn(:options, "/")
      conn = %{conn | host: "burrow.test"}
      conn = Dispatcher.call(conn, Dispatcher.init([]))

      assert get_resp_header(conn, "access-control-allow-origin") == ["*"]
      assert conn.status == 200
    end

    test "subdomain OPTIONS request returns CORS headers" do
      conn = conn(:options, "/")
      conn = %{conn | host: "myapp.burrow.test"}
      conn = TunnelEndpoint.call(conn, TunnelEndpoint.init([]))

      assert get_resp_header(conn, "access-control-allow-origin") == ["*"]
      assert conn.status == 200
    end
  end
end
