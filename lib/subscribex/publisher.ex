defmodule Subscribex.Publisher do
  @moduledoc false

  use Supervisor

  alias Subscribex.Publisher.Pool
  alias Subscribex.Broker

  def start_link(broker), do: start_link(broker, 1)

  def start_link(broker, count) do
    Supervisor.start_link(__MODULE__, {broker, count})
  end

  def init({broker, count}) do
    import Supervisor.Spec
    connection_name = :"#{broker}.Publisher.Connection"

    children = [
      worker(Subscribex.Connection, [
        Broker.rabbit_host(broker),
        connection_name
      ]),
      supervisor(Pool, [broker, count, connection_name])
    ]

    supervise(children, strategy: :one_for_one, name: :"#{broker}.Publisher.Supervisor")
  end

  def publish(broker, exchange, routing_key, message, options \\ []) do
    {:ok, channel} = Pool.random_publisher(broker)

    Broker.publish(channel, exchange, routing_key, message, options)
  end

  def publish_sync(broker, exchange, routing_key, message, options \\ []) do
    {:ok, channel} = Pool.random_publisher(broker)

    Broker.publish_sync(channel, exchange, routing_key, message, options)
  end
end
