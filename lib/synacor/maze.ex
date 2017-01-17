defmodule Synacor.Maze do
  @moduledoc """
  Functions to work with the maze embedded in the binary file
  Assumes `challenge.bin` file has already been decrypted

  The challenge.bin file has the text encrypted, you need to run until the main loop
  is executed to decrypt the text. Then it can be accessed by these functions
  
  Strings are pascal-style, the first instruction tells how many letters follow
  Lists have a leading instruction telling the length of the list
  
  Address 2732 holds the address of the current room
  Starting room is at address 2317 (read from address 2732)
  First instruction is a pointer to the room title
  Second instruction is a pointer to the room description
  Third instruction is a pointer to a list of possible directions
   The list is pointers to direction strings
  Fourth instruction is a pointer to a list of the rooms for the given directions
  Fifth instruction is items?
  There appear to be blocks that don't quite match this pattern, maybe still encrypted?

  The items table is at offset 27381, which holds the number of items
  27382 holds the ptr to the first item (2668)

  Item structure:
  2668 -> name ptr
  2669 -> description ptr
  2670 -> room number where item is located
  2671 -> ? seems like a function ptr. Maybe the USE behavior?
  """

  alias Synacor.Token
  alias Graphvix.{Graph, Node, Edge}

  defmodule Room do
    defstruct offset: nil, title: nil, description: nil, neighbors: [], node_id: nil
  end

  defmodule Item do
    defstruct offset: nil, name: nil, description: nil, location: nil
  end

  @doc """
  Generate a string that will solve the maze
  """
  def solve do
    steps = [
      "take tablet",
      "bring 2680",
      "take lit lantern",
      "jump 2452",
      "take red coin",
      "jump 2478",
      "take blue coin",
      "jump 2483",
      "take shiny coin",
      "jump 2468",
      "take concave coin",
      "jump 2473",
      "take corroded coin",
      "jump 2463",
      "take teleporter",
      "jump 2457"
      ]

    steps
  end

  @default_start_offset 2317
  @item_list_offset 27381
  @current_room_ptr 2732

  @coins %{
    2 => :red,
    3 => :corroded,
    5 => :shiny,
    7 => :concave,
    9 => :blue
    }

  @doc """
  Solve the door equation:
  _ + _ * _^2 + _^3 - _ = 399

  Answer:
  [9, 2, 5, 7, 3]
  [:blue, :red, :shiny, :concave, :corroded]
  """
  def solve_door do
    options = Map.keys(@coins)
    for a <- options, b <- options, c <- options, d <- options, e <- options do
      result = door_eqn(a, b, c, d, e) |> round
      if 399 == result do
        [a, b, c, d, e]
        |> IO.inspect
        |> Enum.map(&(Map.get(@coins, &1)))
        |> IO.inspect
      end
      result
    end
  end

  # _ + _ * _^2 + _^3 - _ = 399
  defp door_eqn(a, b, c, d, e) do
    a + b * :math.pow(c, 2) + :math.pow(d, 3) - e
  end

  @doc """
  Jump to the specified room offset
  """
  def jump(offset) do
    Synacor.poke(@current_room_ptr, offset)
  end

  @doc """
  Generate a Graphviz graph of the maze
  """
  def graph(bin) do
    rooms = read_all_rooms(bin)
    items = read_all_items(bin)
    graph(rooms, items)
  end
  def graph(room_map = %{}, items = %{}) do
    Graph.new(:maze)

    room_map
    |> add_nodes(items)
    |> Enum.reduce(Map.new, &add_map/2)
    |> add_links

    Graph.graph
  end

  defp add_nodes(list, items) do
    list
    |> Enum.map(&(add_room_node(&1, items)))
  end

  defp add_room_node({_, room = %Room{title: title, description: description, offset: offset}}, items) do
    desc = String.replace("#{description}", ~s("), ~s('))
    label = "#{title} (#{inspect offset})\n#{desc}"
    label = case Map.get(items, offset, nil) do
      nil -> label
      item -> label <> "\n\n\nItem: #{item.name}\n#{item.description}"
    end
    {node_id, _} = Node.new(label: label)
    if @default_start_offset == offset do
      Node.update(node_id, color: "green")
    end
    %Room{room | node_id: node_id}
  end

  defp add_map(room = %Room{offset: offset}, acc) do
    Map.put(acc, offset, room)
  end

  defp add_links(map) do
    map
    |> Map.values
    |> Enum.map(&(add_room_links(&1, map)))
  end

  defp add_room_links(%Room{node_id: id, neighbors: neighbors}, map) do
    neighbors
    |> Enum.map(&(add_room_link(id, &1, map)))
  end

  defp add_room_link(node_id, {direction, neigh_offset}, map) do
    neigh = Map.get(map, neigh_offset)
    Edge.new(node_id, neigh.node_id, label: direction)
  end

  @doc """
  Read all rooms
  """
  def read_all_rooms(start_room_offset \\ @default_start_offset, bin) do
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

  @doc """
  Read all items
  """
  def read_all_items(start_item_offset \\ @item_list_offset, bin) do
    num_items = Token.get_value(start_item_offset, bin)
    read_next_item(num_items, start_item_offset+1, bin, Map.new)
  end

  defp read_next_item(0, _, _, acc), do: acc
  defp read_next_item(num_items, offset, bin, acc) do
    item_ptr = Token.get_value(offset, bin)
    item = read_item(item_ptr, bin)
    read_next_item(num_items - 1, offset + 1, bin, Map.put(acc, item.location, item))
  end
  
  @doc """
  Read one item from a binary
  """
  def read_item(offset, bin) do
    name = get_string_ptr(offset, bin)
    desc = get_string_ptr(offset+1, bin)
    desc = String.replace("#{desc}", ~s("), ~s('))
    loc = Token.get_value(offset+2, bin)
    %Item{offset: offset, name: name, description: desc, location: loc}
  end

  @doc """
  Move an item to a new location
  """
  def move_item(item_offset) do
    move_item(item_offset, current_room())
  end
  def move_item(item_offset, location_offset) do
    Synacor.poke(item_offset+2, location_offset)
  end

  @doc """
  Return the current room offset
  """
  def current_room do
    map = Synacor.peek(@current_room_ptr)
    [result] = map.value
    result
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
