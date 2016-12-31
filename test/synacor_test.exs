defmodule SynacorTest do
  use ExUnit.Case
  doctest Synacor

  test "sample code" do
    bin = <<9::little-integer-size(16),
    32768::little-integer-size(16),
    32769::little-integer-size(16),
    4::little-integer-size(16),
    19::little-integer-size(16),
    32768::little-integer-size(16)>>

    state = Synacor.execute(bin)
    assert 4 == Enum.at(state.registers, 0)
  end

end
