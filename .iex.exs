alias Subscribex.TestBroker

defmodule Test do
  alias Subscribex.Rabbit

  @exchange "test-exchange"
  @queue "test-queue"
  @routing_key "routing_key"

  def test do
    TestBroker.channel(fn channel ->
      for _ <- 0..1000 do
        Rabbit.declare_exchange(channel, @exchange, :topic, durable: true)
        Rabbit.declare_queue(channel, @queue, [])
        Rabbit.bind_queue(channel, @queue, @exchange, routing_key: @routing_key)

        TestBroker.publish(channel, @exchange, @routing_key, "message")
      end
    end)
  end
end

Subscribex.TestBroker.start_link()
