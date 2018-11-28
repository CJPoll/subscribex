defmodule Subscribex.TestSubscriber do
  @moduledoc false

  use Subscribex.Subscriber

  @preprocessors &__MODULE__.deserialize/1

  def start_link(broker) do
    Subscribex.Subscriber.start_link(__MODULE__, broker)
  end

  def init(broker) do
    config = %Config{
      auto_ack: false,
      broker: broker,
      queue: "test-queue",
      prefetch_count: 1000,
      exchange: "test-exchange",
      exchange_type: :topic,
      exchange_opts: [durable: true],
      binding_opts: [routing_key: "routing_key"]
    }

    {:ok, config}
  end

  def deserialize(payload) do
    IO.inspect("Deserializing #{payload}")
    :hello
  end

  def second(:hello) do
    # IO.inspect("Second!")
    :hi
  end

  def handle_payload(_payload, channel, delivery_tag, _redelivered) do
    # IO.inspect(payload)
    ack(channel, delivery_tag)
  end
end
