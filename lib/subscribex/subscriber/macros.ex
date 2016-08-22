defmodule Subscribex.Subscriber.Macros do
  defmacro routing_key(routing_key) do
    quote do
      def routing_key, do: unquote(routing_key)
    end
  end

  defmacro queue(queue_name) do
    quote do
      def queue, do: unquote(queue_name)
    end
  end

  defmacro exchange(exchange_name) do
    quote do
      def exchange, do: unquote(exchange_name)
    end
  end

  defmacro manual_ack! do
    quote do
      def auto_ack?, do: false
    end
  end

  defmacro provide_channel! do
    quote do
      def provide_channel?, do: true
    end
  end

  defmacro durable! do
    quote do
      def durable?, do: true
    end
  end

  defmacro prefetch_count(count) do
    quote do
      def prefetch_count, do: unquote(count)
    end
  end
end
