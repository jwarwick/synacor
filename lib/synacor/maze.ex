defmodule Synacor.Maze do
  @moduledoc """
  Functions to work with the maze embedded in the binary file
  Assumes `challenge.bin` file has already been decrypted
  """

  alias Synacor.Token

  # The challenge.bin file has the text encrypted, you need to run until the main loop
  # is executed to decrypt the text. Then it can be accessed by these functions
  #
  # Strings are pascal-style, the first instruction tells how many letters follow
  # Lists have a leading instruction telling the length of the list
  #
  # Starting room is at address 2317 (read from address 2732)
  # First instruction is a pointer to the room title
  # Second instruction is a pointer to the room description
  # Third instruction is a pointer to a list of possible directions
  #  The list is pointers to direction strings
  # Fourth instruction is a pointer to another block of data: TBD

  defmodule Room do
    defstruct offset: nil, title: nil, description: nil, directions: []
  end
  
  @doc """
  Read one room from a binary
  """
  def read_room(offset, bin) do
    title = get_string_ptr(offset, bin)
    desc = get_string_ptr(offset+1, bin)
    dir_list = get_string_ptr(offset+2, bin)
    dirs = Enum.map(dir_list, &(read_string(&1, bin)))
    %Room{offset: offset, title: title, description: desc, directions: dirs}
  end

  defp get_string_ptr(offset, bin) do
    Token.get_value(offset, bin)
    |> read_string(bin)
  end

  @doc """
  Read a string encoded into the binary
  """
  def read_string(offset, bin), do: read_length_encoded_data(offset, bin)

  defp read_length_encoded_data(offset, bin) do
    len = Token.get_value(offset, bin)
    read_data(len, offset+1, bin, [])
  end

  defp read_data(0, _offset,_bin, acc), do: Enum.reverse(acc)
  defp read_data(cnt, offset, bin, acc) do
    op = Token.get_value(offset, bin)
    read_data(cnt-1, offset+1, bin, [op | acc])
  end

end
