defmodule Synacor.Terminal do
  @moduledoc """
  Interactive terminal for executing the Synacor VM
  """

  alias Synacor.Token
  alias Synacor.Maze
  
  defmodule State do
    defstruct pid: nil, halt: false, file_base: nil, input: []
  end

  @doc """
  Execute the given binary
  """
  def run(bin \\ "challenge.bin") do
    {:ok, pid} = Synacor.start_link(bin, self())
    loop(%State{pid: pid})
  end

  defp loop(%State{halt: true}) do
    IO.puts "Stopping"
    Synacor.shutdown()
  end
  defp loop(state) do
    new_state = receive do
      {:output, val} ->
        write_output(val)
        state
      unknown ->
        IO.puts "Unknown input: #{inspect unknown}"
        state
    after
      250 ->
        get_input(state)
    end
    loop(new_state)
  end

  defp write_inspect_output(data) do
    write_output("#{IO.ANSI.magenta()}#{inspect data}#{IO.ANSI.reset()}\n")
  end

  defp write_output(val) do
    IO.write([IO.ANSI.green(), val, IO.ANSI.reset()])
  end

  defp get_input(state = %State{input: []}) do
    IO.gets(IO.ANSI.blue() <> "> " <> IO.ANSI.white() <> IO.ANSI.bright() <> IO.ANSI.reset())
    |> String.trim
    |> handle_input(state)
  end
  defp get_input(state = %State{input: [head | rest]}) do
    IO.puts "Executing #{head}"
    state = 
      head
      |> String.trim
      |> handle_input(state)
    %State{state | input: rest}
  end

  defp handle_input("quit", state) do
    %State{state | halt: true}
  end
  defp handle_input("load " <> path, state) do
    path
    |> String.replace("\"", "")
    |> String.trim
    |> Synacor.load

    IO.puts "#{IO.ANSI.white()}#{IO.ANSI.bright()}VM is paused. `cont` to start running.#{IO.ANSI.reset()}"

    %State{state | file_base: Path.rootname(path)}
  end
  defp handle_input("save " <> path, state) do
    path
    |> String.replace("\"", "")
    |> String.trim
    |> Synacor.save

    %State{state | file_base: Path.rootname(path)}
  end
  defp handle_input("dump " <> path, state) do
    path
    |> String.replace("\"", "")
    |> String.trim
    |> do_dump

    %State{state | file_base: Path.rootname(path)}
  end
  defp handle_input("checkpoint", state = %State{file_base: base}) do
    Synacor.save("#{base}.state")
    do_dump("#{base}.asm")

    state
  end
  defp handle_input("annotate " <> str, state) do
    str
    |> String.trim
    |> String.split
    |> handle_annotate
    state
  end
  defp handle_input("state", st) do
    Synacor.state
    |> write_inspect_output
    st
  end
  defp handle_input("set_register " <> args, state) do
    [reg_offset, value] =
      args
      |> String.trim
      |> String.split
      |> Enum.map(&get_integer/1)
    Synacor.set_register(reg_offset, value)
    state
  end
  defp handle_input("bt", state) do
    Synacor.call_stack
    |> Enum.map(&write_inspect_output/1)
    state
  end
  defp handle_input("break", state) do
    Synacor.break
    state
  end
  defp handle_input("step", state) do
    Synacor.step
    state
  end
  defp handle_input("next", state) do
    Synacor.next
    state
  end
  defp handle_input("cont", state) do
    Synacor.continue
    state
  end
  defp handle_input("ret", state) do
    Synacor.ret
    state
  end
  defp handle_input("stack_up", state) do
    Synacor.up
    state
  end
  defp handle_input("jump" <> addr, state) do
    addr
    |> get_integer
    |> Maze.jump
    state
  end
  defp handle_input("bring" <> addr, state) do
    addr
    |> get_integer
    |> Maze.move_item
    state
  end
  defp handle_input("peek" <> addr, state) do
    addr
    |> get_integer
    |> Synacor.peek
    |> write_inspect_output
    state
  end
  defp handle_input("poke " <> args, state) do
    [address, value] =
      args
      |> String.trim
      |> String.split
      |> Enum.map(&get_integer/1)
    Synacor.poke(address, value)
    state
  end
  defp handle_input("add_break" <> addr, state) do
    addr
    |> get_integer
    |> Synacor.add_break
    state
  end
  defp handle_input("clear_break", state) do
    Synacor.clear_break
    state
  end
  defp handle_input("solve", state) do
    %State{state | input: Maze.solve}
  end
  defp handle_input("", state) do
    state
  end
  defp handle_input(str, state) do
    Synacor.input(str)
    state
  end

  defp get_integer(str) do
    str
    |> String.replace(",", "")
    |> String.trim
    |> String.to_integer
  end

  defp handle_annotate([str]) do
    Synacor.annotate(str)
  end
  defp handle_annotate([pc | rest]) do
    str = Enum.join(rest, " ")
    Synacor.annotate(get_integer(pc), str)
  end

  defp do_dump(path) do
    syn_state = Synacor.state()
    Token.disassemble(syn_state.instructions, path, syn_state.annotations)
  end

end
