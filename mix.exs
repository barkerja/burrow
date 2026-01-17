defmodule Burrow.MixProject do
  use Mix.Project

  def project do
    [
      app: :burrow,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases()
    ]
  end

  defp releases do
    [
      burrow: [
        include_executables_for: [:unix],
        applications: [runtime_tools: :permanent],
        steps: [:assemble, :tar]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto, :ssl, :public_key, :inets],
      mod: {Burrow.Application, []}
    ]
  end

  defp deps do
    [
      {:bandit, "~> 1.9.0"},
      {:plug, "~> 1.19.1"},
      {:mint, "~> 1.7.1"},
      {:mint_web_socket, "~> 1.0.5"},
      {:websock_adapter, "~> 0.5.9"},
      {:jason, "~> 1.4.4"},
      # ACME/Let's Encrypt support
      {:jose, "~> 1.11"},
      {:x509, "~> 0.8"},
      # Request inspector web UI
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_html, "~> 4.2"},
      {:phoenix_pubsub, "~> 2.1"},
      # GitHub OAuth for inspector auth
      {:ueberauth, "~> 0.10"},
      {:ueberauth_github, "~> 0.8"},
      # Distributed Erlang clustering
      {:dns_cluster, "~> 0.2.0"}
    ]
  end
end
