defmodule Synacor.Token do
  @moduledoc """
  Tokenize binary data into instructions
  """

  @doc """
  Get the value at the given memory address
  """
  def get_value(offset, bin) do
    skip = offset * 2
    <<_skip::binary-size(skip), value::little-integer-size(16), _rest::binary>> = bin
    value
  end

  @doc """
  Put the value at the given memory address
  """
  def put_value(value, offset, bin) do
    skip = offset * 2
    <<skip::binary-size(skip), _old::little-integer-size(16), rest::binary>> = bin
    skip <> <<value::little-integer-size(16)>> <> rest
  end

  @doc """
  Parse the instruction at the given offset
  """
  def analyze_one(offset, bin) do
    skip = offset * 2
    <<_skip::binary-size(skip), rest::binary>> = bin
    {op, _rest} = next_token(rest)
    op
  end

  @doc """
  Write chars found in output instructions in a file
  """
  def strings(path) do
    path
    |> analyze_file
    |> Enum.filter(&is_out/1)
    |> Enum.each(&write_out/1)
    |> IO.inspect
  end

  @doc """
  Generate a list of instructions from a file
  """
  def analyze_file(path) do
    path
    |> File.read!
    |> analyze
  end

  @doc """
  Generate a list of instructions from a binary
  """
  def analyze(bin) do
    bin
    |> analyze([])
  end

  defp analyze(<<>>, acc), do: Enum.reverse(acc)
  defp analyze(bin, acc) do
    {op, rest} = next_token(bin)
    analyze(rest, [op | acc])
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

  for {name, value, args} <- @opcodes do
    IO.puts "Adding #{inspect name}: #{inspect value}"
    defp next_token(<<unquote(value)::little-integer-size(16), rest::binary>>) do
      # IO.puts "Parsed: #{inspect unquote(name)}, #{inspect unquote(value)}, #{inspect unquote(args)}"
      take_args(unquote(name), unquote(args), rest)
    end
  end

  defp next_token(<<value::little-integer-size(16), rest::binary>>) do
    IO.puts "Unknown opcode: #{inspect value}"
    {{:unknown, value}, rest}
  end
  defp next_token(<<value, rest::binary>>) do
    IO.puts "Unknown single byte: #{inspect value}"
    {{:unknown_byte, value}, rest}
  end
  defp next_token(<<>>) do
    {{:end_of_stream}, <<>>}
  end

  defp take_args(name, 0, rest), do: {{name}, rest}
  defp take_args(name, 1, <<v::little-integer-size(16), rest::binary>>), do: {{name, value(v)}, rest}
  defp take_args(name, 2, <<v::little-integer-size(16), v1::little-integer-size(16), rest::binary>>), do: {{name, value(v), value(v1)}, rest}
  defp take_args(name, 3, <<v::little-integer-size(16), v1::little-integer-size(16), v2::little-integer-size(16), rest::binary>>), do: {{name, value(v), value(v1), value(v2)}, rest}

  defp value(v) when v <= 32767, do: {:value, v}
  defp value(v) when v >= 32768 and v <= 32775, do: {:reg, v - 32768}

  defp is_out({:out, _val}), do: true
  defp is_out({:unknown, _val}), do: true
  defp is_out(_), do: false

  defp write_out({:out, {:value, val}}), do: val |> List.wrap |> IO.write
  defp write_out({:out, {:reg, _val}}), do: :ok
  defp write_out({:unknown, val}) do
    if String.printable?(to_string([val])) do
      val |> List.wrap |> IO.write
    end
  end
end
