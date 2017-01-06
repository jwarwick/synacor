defmodule Synacor do
  @moduledoc """
  Synacor Virtual Machine interpreter
  """
  use GenServer
  alias Synacor.Token
  use Bitwise

  defmodule State do
    defstruct pc: 0,
              instructions: nil,
              registers: [0, 0, 0, 0, 0, 0, 0, 0],
              stack: [],
              input: "",
              halt: false,
              terminal: nil
  end

  ## API
  ##

  @doc """
  Run the given executable file on the VM
  """
  def start_link(path, terminal \\ nil) do
    GenServer.start_link(__MODULE__, %{path: path, terminal: terminal}, name: __MODULE__)
  end

  @doc """
  Give input to the engine
  """
  def input(str) do
    GenServer.cast(__MODULE__, {:input, str})
  end

  @doc """
  Shutdown the VM
  """
  def shutdown(reason \\ :normal) do
    GenServer.stop(__MODULE__, reason)
  end

  @doc """
  Evaluate an instruction in the current state
  Does *not* update the program counter
  """
  def evaluate(instruction) do
    GenServer.cast(__MODULE__, {:evaluate, instruction})
  end

  @doc """
  Get VM state
  """
  def state do
    GenServer.call(__MODULE__, {:get_state})
  end

  @doc """
  Set the VM state
  """
  def set_state(state) do
    GenServer.cast(__MODULE__, {:set_state, state})
  end

  @doc """
  Get registers
  """
  def registers, do: state().registers

  @doc """
  Set register
  """
  def set_register(index, value) do
    state = state()
    registers = List.replace_at(state.registers, index, value)
    set_state(%State{state | registers: registers})
  end

  @doc """
  Get the stack
  """
  def stack, do: state().stack

  @doc """
  Get a memory location
  """
  def peek(address) do
    instructions = state().instructions
    Token.get_value(address, instructions)
  end

  @doc """
  Set a memory location
  """
  def poke(address, value) do
    state = state()
    instructions = Token.put_value(value, address, state.instructions)
    set_state(%State{state | instructions: instructions})
  end

  ## Implementation
  ##

  def init(%{path: path, terminal: terminal}) do
    bin = File.read!(path)
    {:ok, %State{instructions: bin, terminal: terminal}, 0}
  end


  def handle_info(:timeout, state) do
    run(state)
  end

  def handle_cast({:input, str}, state) do
    {:noreply, %State{state | input: str <> "\n"}, 0}
  end
  def handle_cast({:set_state, new_state}, _state) do
    {:noreply, new_state, 0}
  end
  def handle_cast({:evaluate, instruction}, state) do
    {new_state, _new_pc} = evaluate(instruction, state)
    {:noreply, new_state, 0}
  end

  def handle_call({:get_state}, _from, state) do
    {:reply, state, state, 0}
  end

  defp run(state = %State{halt: true}) do
    {:noreply, state}
  end
  defp run(state = %State{pc: pc, instructions: instructions}) do
    i = Token.get_instruction(pc, instructions)
    # IO.puts "#{inspect pc}: #{inspect i}, reg: #{inspect state.registers}"
    {new_state, new_pc} = evaluate(i, state)
    {:noreply, %State{new_state | pc: new_pc}, 0}
  end

  # NOTE: evaluate does *not* update the PC in the state
  # It passes the new PC in the returned tuple

  defp evaluate({:noop}, state) do
    {state, state.pc + 1}
  end
  defp evaluate({:out, val}, state) do
    val = get_value(val, state)
    write_output(val, state)
    {state, state.pc + 2}
  end
  defp evaluate({:in, _reg}, state = %State{input: ""}) do
    {state, state.pc}
  end
  defp evaluate({:in, {:reg, r}}, state = %State{input: <<char, rest::binary>>}) do
    state = %State{state | input: rest}
    |> set_register(r, {:value, char})
    {state, state.pc + 2}
  end
  defp evaluate({:add, {:reg, r}, b, c}, state) do
    b = get_value(b, state)
    c = get_value(c, state)
    sum = Integer.mod(b + c, 32768)
    state = set_register(state, r, {:value, sum})
    {state, state.pc + 4}
  end
  defp evaluate({:mult, {:reg, r}, b, c}, state) do
    b = get_value(b, state)
    c = get_value(c, state)
    mult = Integer.mod(b * c, 32768)
    state = set_register(state, r, {:value, mult})
    {state, state.pc + 4}
  end
  defp evaluate({:mod, {:reg, r}, b, c}, state) do
    b = get_value(b, state)
    c = get_value(c, state)
    d = Integer.mod(rem(b, c), 32768)
    state = set_register(state, r, {:value, d})
    {state, state.pc + 4}
  end
  defp evaluate({:eq, {:reg, reg}, b, c}, state) do
    b = get_value(b, state)
    c = get_value(c, state)
    eq = if b == c do
      1
    else
      0
    end
    state = set_register(state, reg, {:value, eq})
    {state, state.pc + 4}
  end
  defp evaluate({:gt, {:reg, reg}, b, c}, state) do
    b = get_value(b, state)
    c = get_value(c, state)
    val = if b > c do
      1
    else
      0
    end
    state = set_register(state, reg, {:value, val})
    {state, state.pc + 4}
  end
  defp evaluate({:and, {:reg, reg}, b, c}, state) do
    b = get_value(b, state)
    c = get_value(c, state)
    state = set_register(state, reg, {:value, band(b,c)})
    {state, state.pc + 4}
  end
  defp evaluate({:or, {:reg, reg}, b, c}, state) do
    b = get_value(b, state)
    c = get_value(c, state)
    state = set_register(state, reg, {:value, bor(b,c)})
    {state, state.pc + 4}
  end
  defp evaluate({:not, {:reg, reg}, b}, state) do
    b = get_value(b, state)
    bn = flip_bits(b)
    state = set_register(state, reg, {:value, bn})
    {state, state.pc + 3}
  end
  defp evaluate({:push, reg}, state = %State{stack: stack}) do
    value = get_value(reg, state)
    new_stack = List.insert_at(stack, 0, value)
    state = %State{state | stack: new_stack}
    {state, state.pc + 2}
  end
  defp evaluate({:pop, {:reg, reg}}, state) do
    {value, state} = pop_stack(state)
    state = set_register(state, reg, {:value, value})
    {state, state.pc + 2}
  end
  defp evaluate({:rmem, {:reg, reg}, b}, state = %State{instructions: instructions}) do
    addr = get_value(b, state)
    value = Token.get_value(addr, instructions)
    state = set_register(state, reg, {:value, value})
    {state, state.pc + 3}
  end
  defp evaluate({:wmem, addr, value}, state = %State{instructions: instructions}) do
    val = get_value(value, state)
    offset = get_value(addr, state)
    new_instructions = Token.put_value(val, offset, instructions)
    state = %State{state | instructions: new_instructions}
    {state, state.pc + 3}
  end
  defp evaluate({:set, {:reg, reg}, val}, state) do
    state = set_register(state, reg, val)
    {state, state.pc + 3}
  end
  defp evaluate({:jmp, val}, state) do
    value = get_value(val, state)
    {state, value}
  end
  defp evaluate({:jt, test, target}, state) do
    value = get_value(test, state)
    if value != 0 do
      {state, get_value(target, state)}
    else
      {state, state.pc + 3}
    end
  end
  defp evaluate({:jf, test, target}, state) do
    value = get_value(test, state)
    if value == 0 do
      {state, get_value(target, state)}
    else
      {state, state.pc + 3}
    end
  end
  defp evaluate({:call, next}, state = %State{pc: pc}) do
    state = push_stack(state, {:value, pc+2})
    {state, get_value(next, state)}
  end
  defp evaluate({:ret}, state) do
    {value, state} = pop_stack(state)
    {state, value}
  end
  defp evaluate({:halt}, state) do
    {%State{state | halt: true}, state.pc}
  end
  defp evaluate(unknown, state) do
    IO.puts "unknown command: #{inspect unknown}"
    {%State{state | halt: true}, state.pc}
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

  defp write_output(val, %State{terminal: nil}) do
    val
    |> List.wrap
    |> IO.write
  end
  defp write_output(val, %State{terminal: terminal}) do
    send(terminal, {:output, val})
  end
end
