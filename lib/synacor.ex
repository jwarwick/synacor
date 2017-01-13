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
              terminal: nil,
              mode: :run,
              target_pc: nil,
              breakpoints: []
  end

  ## API
  ##

  @doc """
  Run the given executable file on the VM
  """
  def start_link(path, terminal \\ nil, mode \\ :run) do
    GenServer.start_link(__MODULE__, %{path: path, terminal: terminal, mode: mode}, name: __MODULE__)
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
  Save the current state to a file
  """
  def save(path) do
    bin = state() |> :erlang.term_to_binary()
    File.write!(path, bin)
  end

  @doc """
  Load a file as the current state.
  Puts the VM into :step mode
  """
  def load(path) do
    bin = File.read!(path)
    state = :erlang.binary_to_term(bin)
    set_state(%State{state | mode: :step})
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

  @doc """
  Continue running a stepped VM
  """
  def continue do
    GenServer.cast(__MODULE__, {:continue})
  end

  @doc """
  Put VM into step mode
  """
  def break do
    GenServer.cast(__MODULE__, {:break})
  end

  @doc """
  Step forward one instruction
  """
  def step do
    GenServer.cast(__MODULE__, {:step})
  end

  @doc """
  Step forward one instruction, don't go into `call`s
  """
  def next do
    GenServer.cast(__MODULE__, {:next})
  end

  @doc """
  Run until the next ret instruction and then break
  """
  def ret do
    GenServer.cast(__MODULE__, {:ret})
  end

  @doc """
  Add a breakpoint
  """
  def add_break(addr) do
    state = state()
    breaks = List.insert_at(state.breakpoints, 0, addr)
    set_state(%State{state | breakpoints: breaks})
  end

  @doc """
  Clear all breakpoints
  """
  def clear_break do
    state = state()
    set_state(%State{state | breakpoints: []})
  end

  ## Implementation
  ##

  def init(%{path: path, terminal: terminal, mode: mode}) do
    bin = File.read!(path)
    {:ok, %State{instructions: bin, terminal: terminal, mode: mode}, 0}
  end

  def handle_info(:timeout, state = %State{mode: :step}) do
    {:noreply, state}
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
  def handle_cast({:continue}, state) do
    {new_state, new_pc} = one_step(state)
    {:noreply, %State{new_state | pc: new_pc, mode: :run}, 0}
  end
  def handle_cast({:step}, state) do
    {new_state, new_pc} = one_step(state)
    print_state(new_state, new_pc)
    {:noreply, %State{new_state | pc: new_pc}}
  end
  def handle_cast({:next}, state) do
    if is_call?(state) do
      target_pc = next_pc(state)
      {:noreply, %State{state | mode: :run_to, target_pc: target_pc}, 0}
    else
      {new_state, new_pc} = one_step(state)
      print_state(new_state, new_pc)
      {:noreply, %State{new_state | mode: :step, pc: new_pc}}
    end
  end
  def handle_cast({:break}, state) do
    print_state(state, state.pc)
    {:noreply, %State{state | mode: :step}, 0}
  end
  def handle_cast({:ret}, state) do
    {:noreply, %State{state | mode: :ret}, 0}
  end

  def handle_call({:get_state}, _from, state) do
    {:reply, state, state, 0}
  end

  defp run(state = %State{halt: true}) do
    {:noreply, state}
  end
  defp run(state = %State{pc: pc, target_pc: pc, mode: :run_to}) do
    print_state(state)
    {:noreply, %State{state | mode: :step}}
  end
  defp run(state = %State{pc: pc}) do
    if Enum.member?(state.breakpoints, pc) do
      write_output("#{IO.ANSI.red()} Hit Breakpoint @ #{inspect pc} #{IO.ANSI.normal()}\n", state)
      print_state(state)
      {:noreply, %State{state | mode: :step}}
    else
      {new_state, new_pc} = one_step(state)
      {:noreply, %State{new_state | pc: new_pc}, 0}
    end
  end

  defp one_step(state = %State{halt: true}) do
    {state, state.pc}
  end
  defp one_step(state = %State{pc: pc, instructions: instructions}) do
    i = Token.get_instruction(pc, instructions)
    evaluate(i, state)
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
  defp evaluate({:ret}, state = %State{mode: :ret, pc: pc}) do
    print_state(state)
    {%State{state | mode: :step}, pc}
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

  defp print_state(state, pc \\ nil) do
    pc = if nil == pc do
      state.pc
    else
      pc
    end
    print_instruction(pc, state)
    write_output("     #{IO.ANSI.magenta()}registers: #{inspect state.registers}#{IO.ANSI.reset()}\n", state)
    write_output("     #{IO.ANSI.blue()}stack: #{inspect state.stack}#{IO.ANSI.reset()}\n", state)
  end

  defp print_instruction(pc, state) do
    i = Token.get_instruction(pc, state.instructions)
    write_output("#{IO.ANSI.magenta()} #{inspect pc}: #{IO.ANSI.green()}#{inspect i}, #{IO.ANSI.reset()}\n", state)
    ins = elem(i, 0)
    size = Token.instruction_length(ins)
    new_pc = pc + size
    i = Token.get_instruction(pc + size, state.instructions)
    write_output("#{IO.ANSI.white()} #{inspect new_pc}: #{IO.ANSI.green()}#{inspect i}, #{IO.ANSI.reset()}\n", state)
  end

  defp is_call?(state) do
    i = Token.get_instruction(state.pc, state.instructions)
    ins = elem(i, 0)
    :call == ins
  end

  defp next_pc(state) do
    i = Token.get_instruction(state.pc, state.instructions)
    ins = elem(i, 0)
    Token.instruction_length(ins) + state.pc
  end
end
