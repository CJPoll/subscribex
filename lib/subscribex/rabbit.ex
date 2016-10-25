defmodule Subscribex.Rabbit do
  def declare_qos(channel, prefetch_count) do
    AMQP.Basic.qos(channel, prefetch_count: prefetch_count)
  end

  def declare_queue(channel, queue, opts) do
    AMQP.Queue.declare(channel, queue, opts)
  end

  def declare_exchange(channel, exchange, exchange_type) do
    AMQP.Exchange.declare(channel, exchange, exchange_type)
  end

  def bind_queue(channel, routing_keys, queue, exchange) do
    Enum.each(routing_keys, fn(routing_key) ->
      AMQP.Queue.bind(channel, queue, exchange, [routing_key: routing_key])
    end)
  end
end
