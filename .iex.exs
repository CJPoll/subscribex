alias Subscribex.{TestBroker, TestSubscriber}

defmodule Test do
  alias Subscribex.Rabbit

  @exchange "test-exchange"
  @queue "test-queue"
  @routing_key "routing_key"

  def test do
    TestBroker.channel(fn channel ->
      Rabbit.declare_exchange(channel, @exchange, :topic, durable: true)
      Rabbit.declare_queue(channel, @queue, [])
      Rabbit.bind_queue(channel, @queue, @exchange, routing_key: @routing_key)
    end)

    Enum.each(0..1_000, fn _ ->
      TestBroker.publish(@exchange, @routing_key, "message")
    end)
  end
end

Subscribex.TestBroker.start_link()
