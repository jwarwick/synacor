defmodule Synacor.Terminal do
  @moduledoc """
  Interactive terminal for executing the Synacor VM
  """
  
  defmodule State do
    defstruct pid: nil, halt: false
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
      750 ->
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

  defp get_input(state) do
    IO.gets(IO.ANSI.blue() <> "> " <> IO.ANSI.white() <> IO.ANSI.bright() <> IO.ANSI.reset())
    |> String.trim
    |> handle_input(state)
  end

  defp handle_input("quit", state) do
    %State{state | halt: true}
  end
  defp handle_input("state", st) do
    Synacor.state
    |> write_inspect_output
    st
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
  defp handle_input("continue", state) do
    Synacor.continue
    state
  end
  defp handle_input("ret", state) do
    Synacor.ret
    state
  end
  defp handle_input("peek" <> addr, state) do
    addr
    |> get_integer
    |> Synacor.peek
    |> write_inspect_output
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
  defp handle_input(str, state) do
    Synacor.input(str)
    state
  end

  defp get_integer(str) do
    str
    |> String.trim
    |> String.to_integer
  end

end
