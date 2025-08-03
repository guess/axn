defmodule AxnTest do
  use ExUnit.Case
  doctest Axn

  test "greets the world" do
    assert Axn.hello() == :world
  end
end
