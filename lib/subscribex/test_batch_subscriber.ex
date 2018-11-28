defmodule Subscribex.TestBatchSubscriber do
  @moduledoc false

  use Subscribex.BatchSubscriber

  def start_link(broker) do
    Subscribex.BatchSubscriber.start_link(__MODULE__, broker)
  end

  def init(broker) do
    config = %Config{
      batch_size: 6,
      binding_opts: [routing_key: "routing_key"],
      broker: broker,
      exchange: "test-exchange",
      exchange_opts: [durable: true],
      exchange_type: :topic,
      max_delay: :timer.seconds(10),
      prefetch_count: 10,
      queue: "test-queue"
    }

    {:ok, config}
  end

  def handle_batch(msgs, channel) do
    IO.inspect(msgs)

    Enum.each(msgs, fn {_payload, delivery_tag, _redelivered} ->
      ack(channel, delivery_tag)
    end)
  end
end
