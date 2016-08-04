defmodule Subscribex.Mixfile do
  use Mix.Project

  def project do
    [app: :subscribex,
     version: "0.1.0",
     elixir: "~> 1.3",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     package: package,
     description: "A high-level library for making RabbitMQ subscribers",
     deps: deps()]
  end

  def application do
    [applications: [:logger]]
  end

  defp deps do
    [{:amqp, "~> 0.1.4"}]
  end

  defp package do
    [licenses: ["MIT"],
     maintainers: ["cjpoll@gmail.com"],
     links: %{"Github" => "http://github.com/cjpoll/subscribex"}]
  end
end
