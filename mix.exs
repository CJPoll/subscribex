defmodule Subscribex.Mixfile do
  use Mix.Project

  def project do
    [app: :subscribex,
     version: "0.3.0",
     elixir: "~> 1.3",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     package: package,
     description: "A high-level library for making RabbitMQ subscribers",
     deps: deps()]
  end

  def application do
    [
      mod: {Subscribex.Application, []},
      applications: [:logger]
    ]
  end

  defp deps do
    [{:amqp, "~> 0.1.4"},
     {:ex_doc, "~> 0.13", only: :dev}]
  end

  defp package do
    [licenses: ["copyleft"],
     maintainers: ["cjpoll@gmail.com"],
     links: %{"Github" => "http://github.com/cjpoll/subscribex"}]
  end
end
