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
  # Address 2732 holds the address of the current room
  # Starting room is at address 2317 (read from address 2732)
  # First instruction is a pointer to the room title
  # Second instruction is a pointer to the room description
  # Third instruction is a pointer to a list of possible directions
  #  The list is pointers to direction strings
  # Fourth instruction is a pointer to a list of the rooms for the given directions
  # Fifth instruction is items?
  # There appear to be blocks that don't quite match this pattern, maybe still encrypted?

  defmodule Room do
    defstruct offset: nil, title: nil, description: nil, neighbors: []
  end

  @doc """
  Read all rooms
  """
  def read_all_rooms(start_room_offset, bin) do
    read_next([start_room_offset], Map.new(), bin)
  end

  defp read_next([], map, _bin), do: map
  defp read_next(l = [room | rest], map, bin) do
    r = read_room(room, bin)
    neighbors =
      r.neighbors
      |> Enum.map(fn {_str, num} -> num end)
      |> Enum.reject(&(Map.has_key?(map, &1)))
      |> Enum.reject(&(Enum.member?(l, &1)))
    read_next(neighbors ++ rest, Map.put(map, r.offset, r), bin)
  end
  
  @doc """
  Read one room from a binary
  """
  def read_room(offset, bin) do
    title = get_string_ptr(offset, bin)
    desc = get_string_ptr(offset+1, bin)
    dir_list = get_string_ptr(offset+2, bin)
    names = Enum.map(dir_list, &(read_string(&1, bin)))
    rooms = get_string_ptr(offset+3, bin)
    z = Enum.zip(names, rooms)
    %Room{offset: offset, title: title, description: desc, neighbors: z}
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
