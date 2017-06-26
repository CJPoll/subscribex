defmodule Subscribex.TestSubscriber do
  @moduledoc false

  use Subscribex.Subscriber

  preprocess &__MODULE__.deserialize/1
  preprocess &__MODULE__.second/1

  def start_link, do: Subscribex.Subscriber.start_link(__MODULE__)

  def init do
    config = %Config{
      queue: "my_queue",
      exchange: "my_exchange",
      exchange_type: :topic,
      binding_opts: [routing_key: "my_key"]
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
    raise "Oh Noez!"
    IO.inspect(payload)
  end

  def handle_error(error, payload) do
    IO.inspect("Error: #{inspect error} for payload: #{inspect payload}")
  end
end
