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
  def run(bin) do
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

  defp write_output(val) do
    IO.write([IO.ANSI.green(), val, IO.ANSI.normal()])
  end

  defp get_input(state) do
    IO.gets(IO.ANSI.blue() <> "> " <> IO.ANSI.white() <> IO.ANSI.bright())
    |> String.trim
    |> handle_input(state)
  end

  defp handle_input("quit", state) do
    %State{state | halt: true}
  end
  defp handle_input(str, state) do
    Synacor.input(str)
    state
  end

end
