defmodule Subscribex.Rabbit do
  @moduledoc false

  def declare_qos(channel, prefetch_count) do
    AMQP.Basic.qos(channel, prefetch_count: prefetch_count)
  end

  def declare_queue(channel, queue, opts) do
    AMQP.Queue.declare(channel, queue, opts)
  end

  def declare_exchange(channel, exchange, exchange_type, exchange_opts) do
    AMQP.Exchange.declare(channel, exchange, exchange_type, exchange_opts)
  end

  def bind_queue(channel, queue, exchange, binding_opts) do
    AMQP.Queue.bind(channel, queue, exchange, binding_opts)
  end
end
