defmodule Subscribex.TestSubscriber do
  @moduledoc false

  use Subscribex.Subscriber

  preprocess &__MODULE__.deserialize/1
  preprocess &__MODULE__.second/1

  def start_link, do: Subscribex.Subscriber.start_link(__MODULE__)

  def init do
    config = %Config{
      queue: "my_queue",
      prefetch_count: 100,
      exchange: "my_exchange",
      exchange_type: :topic,
      binding_opts: [routing_key: "my_key"],
      auto_ack: true
    }

    {:ok, config}
  end

  def deserialize(payload) do
    IO.inspect("Deserializing #{payload}")
    :hello
  end

  def second(:hello) do
    IO.inspect("Second!")
    :hi
  end

  def handle_payload(payload, _channel, _delivery_tag) do
    IO.inspect(payload)
  end
end
