defmodule Subscribex.TestSubscriber do
  @moduledoc false

  use Subscribex.Subscriber

  preprocess(&__MODULE__.deserialize/1)
  preprocess(&__MODULE__.second/1)

  def start_link(broker) do
    Subscribex.Subscriber.start_link(__MODULE__, broker)
  end

  def init(broker) do
    config = %Config{
      broker: broker,
      # "test-queue",
      queue: :queue,
      prefetch_count: 1000,
      exchange: "test-exchange",
      exchange_type: :topic,
      exchange_opts: [durable: true],
      binding_opts: [routing_key: "routing_key"]
    }

    {:ok, config}
  end

  def deserialize(_payload) do
    # IO.inspect("Deserializing #{payload}")
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
