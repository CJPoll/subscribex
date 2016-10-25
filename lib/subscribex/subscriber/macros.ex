defmodule Subscribex.Subscriber.Macros do
  defmacro preprocess(preprocessor) do
    quote do
      @preprocessors unquote(preprocessor)
    end
  end
end
