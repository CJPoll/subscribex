defmodule Subscribex.Mixfile do
  use Mix.Project

  @version "0.10.0-rc.1"

  def project do
    [
      app: :subscribex,
      version: @version,
      elixir: "~> 1.3",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      package: package(),
      description: "A high-level library for making RabbitMQ subscribers",
      dialyzer: [
        plt_add_apps: [:amqp],
        flags: [
          "-Werror_handling",
          "-Wrace_conditions",
          "-Woverspecs"
        ]
      ],
      deps: deps(),
      aliases: aliases(),

      # Docs
      name: "Subscribex",
      docs: docs()
    ]
  end

  def aliases() do
    [compile: ["compile --warnings-as-errors"]]
  end

  def application do
    [
      applications: [:logger]
    ]
  end

  defp deps do
    [
      {:amqp, "~> 0.3.0"},
      {:ex_doc, "~> 0.19", only: :dev},
      {:dialyxir, "0.3.5", only: :dev}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      maintainers: ["cjpoll@gmail.com"],
      links: %{"Github" => "http://github.com/cjpoll/subscribex"}
    ]
  end

  defp docs do
    [
      main: "Subscribex",
      source_ref: "v#{@version}",
      canonical: "http://hexdocs.pm/subscribex",
      source_url: "https://github.com/cjpoll/subscribex",
      extras: [
        "guides/Getting Started.md",
        "guides/Utilizing Subscribers.md"
      ],
      groups_for_modules: [
        # Subscribex,
        "Broker specification": [
          Subscribex.Broker
        ],
        "Subscriber specification": [
          Subscribex.Subscriber,
          Subscribex.Subscriber.Config,
          Subscribex.BatchSubscriber,
          Subscribex.BatchSubscriber.Config
        ],
      ]
    ]
  end
end
