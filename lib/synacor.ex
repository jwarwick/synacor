defmodule Synacor do
  @moduledoc """
  Synacor Virtual Machine interpreter
  """
  alias Synacor.Token
  use Bitwise

  defmodule State do
    defstruct pc: 0,
              instructions: nil,
              registers: [0, 0, 0, 0, 0, 0, 0, 0],
              stack: [],
              input: "",
              halt: false
  end

  @doc """
  Execute the given file
  """
  def execute_file(path) do
    path
    |> File.read!
    |> execute
  end

  @doc """
  Give input to the engine
  """
  def input(str) do
  end

  @doc """
  Execute the given binary instructions
  """
  def execute(bin) do
    run(%State{instructions: bin})
  end

  defp run(state = %State{halt: true}) do
    state
  end
  defp run(state = %State{pc: pc, instructions: instructions}) do
    i = Token.analyze_one(pc, instructions)
    # IO.puts "#{inspect pc}: #{inspect i}"
    new_state = step(i, state)
    run(new_state)
  end

  defp step({:noop}, state) do
    increment_pc(state, 1)
  end
  defp step({:out, val}, state) do
    get_value(val, state)
    |> List.wrap
    |> IO.write
    increment_pc(state, 2)
  end
  defp step({:add, {:reg, r}, b, c}, state) do
    b = get_value(b, state)
    c = get_value(c, state)
    sum = Integer.mod(b + c, 32768)
    state = set_register(state, r, {:value, sum})
    increment_pc(state, 4)
  end
  defp step({:mult, {:reg, r}, b, c}, state) do
    b = get_value(b, state)
    c = get_value(c, state)
    mult = Integer.mod(b * c, 32768)
    state = set_register(state, r, {:value, mult})
    increment_pc(state, 4)
  end
  defp step({:mod, {:reg, r}, b, c}, state) do
    b = get_value(b, state)
    c = get_value(c, state)
    d = Integer.mod(rem(b, c), 32768)
    state = set_register(state, r, {:value, d})
    increment_pc(state, 4)
  end
  defp step({:eq, {:reg, reg}, b, c}, state) do
    b = get_value(b, state)
    c = get_value(c, state)
    eq = if b == c do
      1
    else
      0
    end
    state = set_register(state, reg, {:value, eq})
    increment_pc(state, 4)
  end
  defp step({:gt, {:reg, reg}, b, c}, state) do
    b = get_value(b, state)
    c = get_value(c, state)
    val = if b > c do
      1
    else
      0
    end
    state = set_register(state, reg, {:value, val})
    increment_pc(state, 4)
  end
  defp step({:and, {:reg, reg}, b, c}, state) do
    b = get_value(b, state)
    c = get_value(c, state)
    state
    |> set_register(reg, {:value, band(b,c)})
    |> increment_pc(4)
  end
  defp step({:or, {:reg, reg}, b, c}, state) do
    b = get_value(b, state)
    c = get_value(c, state)
    state
    |> set_register(reg, {:value, bor(b,c)})
    |> increment_pc(4)
  end
  defp step({:not, {:reg, reg}, b}, state) do
    b = get_value(b, state)
    bn = flip_bits(b)
    state
    |> set_register(reg, {:value, bn})
    |> increment_pc(3)
  end
  defp step({:push, reg}, state = %State{stack: stack}) do
    value = get_value(reg, state)
    new_stack = List.insert_at(stack, 0, value)
    %State{state | stack: new_stack}
    |> increment_pc(2)
  end
  defp step({:pop, {:reg, reg}}, state) do
    {value, state} = pop_stack(state)
    state
    |> set_register(reg, {:value, value})
    |> increment_pc(2)
  end
  defp step({:rmem, {:reg, reg}, b}, state = %State{instructions: instructions}) do
    addr = get_value(b, state)
    value = Token.get_value(addr, instructions)
    state
    |> set_register(reg, {:value, value})
    |> increment_pc(3)
  end
  defp step({:wmem, addr, value}, state = %State{instructions: instructions}) do
    val = get_value(value, state)
    offset = get_value(addr, state)
    new_instructions = Token.put_value(val, offset, instructions)
    %State{state | instructions: new_instructions}
    |> increment_pc(3)
  end
  defp step({:set, {:reg, reg}, val}, state) do
    state
    |> set_register(reg, val)
    |> increment_pc(3)
  end
  defp step({:jmp, val}, state) do
    jump_pc(state, val)
  end
  defp step({:jt, test, target}, state) do
    value = get_value(test, state)
    if value != 0 do
      jump_pc(state, target)
    else
      increment_pc(state, 3)
    end
  end
  defp step({:jf, test, target}, state) do
    value = get_value(test, state)
    if value == 0 do
      jump_pc(state, target)
    else
      increment_pc(state, 3)
    end
  end
  defp step({:call, next}, state = %State{pc: pc}) do
    state
    |> push_stack({:value, pc+2})
    |> jump_pc(next)
  end
  defp step({:ret}, state) do
    {value, state} = pop_stack(state)
    state
    |> jump_pc({:value, value})
  end
  defp step({:halt}, state) do
    %State{state | halt: true}
  end
  defp step(unknown, state) do
    IO.puts "unknown command: #{inspect unknown}"
    %State{state | halt: true}
  end

  defp increment_pc(state = %State{pc: pc}, step) do
    %State{state | pc: pc + step}
  end

  defp jump_pc(state, target) do
    %State{state | pc: get_value(target, state)}
  end

  defp get_value({:value, v}, _state), do: v
  defp get_value({:reg, v}, %State{registers: registers}) do
    Enum.at(registers, v)
  end

  defp set_register(state = %State{registers: registers}, reg, value) do
    value = get_value(value, state)
    registers = List.replace_at(registers, reg, value)
    %State{state | registers: registers}
  end

  defp push_stack(state = %State{stack: stack}, value) do
    stack = List.insert_at(stack, 0, get_value(value, state))
    %State{state | stack: stack}
  end

  defp pop_stack(state = %State{stack: stack}) do
    {value, new_stack} = List.pop_at(stack, 0)
    {value, %State{state | stack: new_stack}}
  end

  defp flip_bits(bin) do
    <<l::integer-size(15)>> = for <<c::size(1) <- <<bin::integer-size(15)>> >>, into: <<>>, do: flip_bit(c)
    l
  end

  defp flip_bit(1), do: <<0::size(1)>>
  defp flip_bit(0), do: <<1::size(1)>>
end
