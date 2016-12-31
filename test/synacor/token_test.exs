defmodule SynacorTest.Token do
  use ExUnit.Case
  doctest Synacor.Token
  alias Synacor.Token

  test "one instruction" do
    assert [{:noop}] == Token.analyze(<<21::little-integer-size(16)>>)
  end

  test "three instructions" do
    assert [{:out, {:value, 16}}, {:noop}, {:halt}] == 
      Token.analyze(<<19::little-integer-size(16), 16::little-integer-size(16), 
                      21::little-integer-size(16), 0::little-integer-size(16)>>)
  end
end
