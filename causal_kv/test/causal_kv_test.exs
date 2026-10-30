defmodule CausalKvTest do
  use ExUnit.Case
  doctest CausalKv

  test "greets the world" do
    assert CausalKv.hello() == :world
  end
end
