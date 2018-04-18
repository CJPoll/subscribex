defmodule Subscribex.TestSubscriber do
  @moduledoc false

  use Subscribex.Subscriber

  preprocess &__MODULE__.deserialize/1
  preprocess &__MODULE__.second/1

  def init do
    config = %Config{

      queue: "my_queue",
      exchange: "my_exchange",
      exchange_type: :topic,
      binding_opts: [routing_key: "my_key"],
      auto_ack: false
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

  def handle_payload(payload, _channel, _delivery_tag, _redelivered) do
    IO.inspect(payload)
    raise "Oh noez!"
  end

  def handle_error(payload, channel, delivery_tag, error) do
    IO.inspect("Error: #{inspect error} for payload: #{inspect payload}")
    reject(channel, delivery_tag, requeue: false)
  end
end
