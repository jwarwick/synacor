defmodule Synacor do
  @moduledoc """
  Synacor Virtual Machine interpreter
  """
  alias Synacor.Token

  defmodule State do
    defstruct pc: 0,
              instructions: [],
              registers: [0, 0, 0, 0, 0, 0, 0, 0],
              stack: [],
              heap: [],
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
  Execute the given binary instructions
  """
  def execute(bin) do
    instructions = bin
    |> Token.analyze
    |> IO.inspect

    run(%State{instructions: instructions})
  end

  defp run(state = %State{halt: true}) do
    state
  end
  defp run(state = %State{pc: pc, instructions: instructions}) do
    i = Enum.at(instructions, pc)
    IO.inspect i
    new_state = step(i, state)
    run(new_state)
  end

  defp step({:noop}, state) do
    increment_pc(state)
  end
  defp step({:out, val}, state) do
    get_value(val, state)
    |> List.wrap
    |> IO.write
    increment_pc(state)
  end
  defp step({:jmp, val}, state) do
    jump_pc(state, val)
  end
  defp step({:set, {:reg, reg}, val}, state = %State{registers: registers}) do
    value = get_value(val, state)
    registers = List.replace_at(registers, reg, value)
    %State{state | registers: registers}
    |> increment_pc
  end
  defp step({:call, next}, state = %State{pc: pc}) do
    state = push_stack(state, {:value, pc+1})
    jump_pc(state, next)
  end
  defp step({:add, {:reg, r}, b, c}, state) do
    b = get_value(b, state)
    c = get_value(c, state)
    sum = b + c
    state = set_register(state, r, {:value, sum})
    increment_pc(state)
  end
  defp step(unknown, state) do
    IO.puts "unknown command: #{inspect unknown}"
    %State{state | halt: true}
  end

  defp increment_pc(state = %State{pc: pc}, step \\ 1) do
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
end
