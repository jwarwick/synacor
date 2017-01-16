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
  def get_instruction(offset, bin) do
    skip = offset * 2
    <<_skip::binary-size(skip), rest::binary>> = bin
    {op, _rest} = next_token(rest)
    op
  end

  def disassemble_file(input_path, output_path) do
    input_path
    |> File.read!
    |> disassemble(output_path)
  end

  @doc """
  Convert a binary to assembly file
  """
  def disassemble(bin, output_path, annotations \\ Map.new) do
    result =
    bin
    |> analyze
    |> Enum.reduce([], &merge_outs/2)
    |> Enum.reverse
    |> Enum.map(&(op_to_string(&1, annotations)))

    File.write!(output_path, result)
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
    |> analyze(0, [])
  end

  defp analyze(<<>>, _pc, acc), do: Enum.reverse(acc)
  defp analyze(bin, pc,  acc) do
    {op, rest} = next_token(bin)
    inc = case op do
      {:unknown, _} -> 1
      value -> tuple_size(value)
    end
    analyze(rest, pc + inc, [{pc, op} | acc])
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

  defp next_token(<<v::little-integer-size(16), rest::binary>>) do
    # IO.puts "Unknown opcode: #{inspect v}"
    {{:unknown, [v]}, rest}
  end
  defp next_token(<<>>) do
    {{:end_of_stream}, <<>>}
  end

  for {name, _value, args} <- @opcodes do
    def instruction_length(unquote(name)), do: 1 + unquote(args)
  end
  def instruction_length(_), do: 1

  defp take_args(name, 0, rest), do: {{name}, rest}
  defp take_args(name, 1, <<v::little-integer-size(16), rest::binary>>), do: {{name, value(v)}, rest}
  defp take_args(name, 2, <<v::little-integer-size(16), v1::little-integer-size(16), rest::binary>>), do: {{name, value(v), value(v1)}, rest}
  defp take_args(name, 3, <<v::little-integer-size(16), v1::little-integer-size(16), v2::little-integer-size(16), rest::binary>>), do: {{name, value(v), value(v1), value(v2)}, rest}

  defp value(v) when v <= 32767, do: {:value, v}
  defp value(v) when v >= 32768 and v <= 32775, do: {:reg, v - 32768}

  defp merge_outs({line, {:out, {:value, ?\n}}}, acc) do
    [{line, {:out_newline, {:value, :newline}}} | acc]
  end
  defp merge_outs({_line, {:out, {:value, x}}}, [{line, {:out, {:value, y}}} | rest]) do
    [{line, {:out, {:value, y ++ [x]}}} | rest]
  end
  defp merge_outs({line, {:out, {:value, x}}}, acc) do
    [{line, {:out, {:value, [x]}}} | acc]
  end
  defp merge_outs(op, acc), do: [op | acc]

  defp op_to_string({line, op}, annotations) do
    line_num = line |> Integer.to_string |> String.pad_leading(5, "0")
    str = "[#{line_num}]  #{inspect op}"
    str = case Map.get(annotations, line) do
      nil -> str
      result -> str <> "\t\t\t\t\# #{result}"
    end
    str <> "\n"
  end
end
