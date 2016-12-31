defmodule Synacor.Token do
  @moduledoc """
  Tokenize binary data into instructions
  """

  @doc """
  Generate a list of instructions from a binary
  """
  def analyze(bin) do
    bin
    |> next_token([])
  end

  # {opcode_name, opcode_value, number of args} 
  @opcodes [
    {:halt, 0, 0},
    {:set, 1, 2},
    {:push, 2, 1},
    {:pop, 3, 1},
    {:eq, 4, 3},
    {:gt, 5, 3},
    {:jmp, 6, 1},
    {:jt, 7, 2},
    {:jf, 8, 2},
    {:add, 9, 3},
    {:mult, 10, 3},
    {:mod, 11, 3},
    {:and, 12, 3},
    {:or, 13, 3},
    {:not, 14, 2},
    {:rmem, 15, 2},
    {:wmem, 16, 2},
    {:call, 17, 1},
    {:ret, 18, 0},
    {:out, 19, 1},
    {:in, 20, 1},
    {:noop, 21, 0}
    ]

  defp next_token(<<>>, acc), do: Enum.reverse(acc)

  for {name, value, args} <- @opcodes do
    IO.puts "Adding #{inspect name}: #{inspect value}"
    defp next_token(<<unquote(value)::little-integer-size(16), rest::binary>>, acc) do
      IO.puts "Parsed: #{inspect unquote(name)}, #{inspect unquote(value)}, #{inspect unquote(args)}"
      {op, rest} = take_args(unquote(name), unquote(args), rest)
      next_token(rest, [op | acc])
    end
  end

  defp next_token(<<value::little-integer-size(16), rest::binary>>, acc) do
    # IO.puts "Unknown opcode: #{inspect value}"
    next_token(rest, [{:unknown, value} | acc])
  end

  defp take_args(name, 0, rest), do: {{name}, rest}
  defp take_args(name, 1, <<v::little-integer-size(16), rest::binary>>), do: {{name, value(v)}, rest}
  defp take_args(name, 2, <<v::little-integer-size(16), v1::little-integer-size(16), rest::binary>>), do: {{name, value(v), value(v1)}, rest}
  defp take_args(name, 3, <<v::little-integer-size(16), v1::little-integer-size(16), v2::little-integer-size(16), rest::binary>>), do: {{name, value(v), value(v1), value(v2)}, rest}

  defp value(v) when v <= 32767, do: {:value, v}
  defp value(v) when v >= 32768 and v <= 32775, do: {:reg, v - 32768}
end
