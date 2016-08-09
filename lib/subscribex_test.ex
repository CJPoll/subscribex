defmodule Subscribex.Test do
  defmacro __using__(_arg) do
    quote do
      use ExUnit.Case

      require Subscribex.Test
      import Subscribex.Test
    end
  end
end
