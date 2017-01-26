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

  use Bitwise
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
      "use tablet",
      "doorway",
      "north",
      "north",
      "bridge",
      "continue",
      "down",
      "east",
      "take empty lantern",
      "west",
      "west",
      "passage",
      "ladder",
      "west",
      "south", 
      "north",
      "take can",
      "use can",
      "use lantern",
      "look",
      "west",
      "ladder",
      "darkness",
      "continue",
      "west",
      "west",
      "west",
      "west",
      "north",
      "take red coin",
      "north",
      "west",
      "take blue coin",
      "up",
      "take shiny coin",
      "down",
      "east",
      "east",
      "take concave coin",
      "down",
      "take corroded coin",
      "up",
      "west",
      "use blue coin",
      "use red coin",
      "use shiny coin",
      "use concave coin",
      "use corroded coin",
      "north",
      "take teleporter",
      "use teleporter",
      "take business card",
      "take strange book",
      "look strange book",
      "poke 5489 21",             # disable call to teleport confirmation function
      "poke 5490 21",
      "poke 5485 6",              # make the return value 6
      "set_register 7 25734",
      "use teleporter",
      "north",
      "north",
      "north",
      "north",
      "north",
      "north",
      "north",
      "east",
      "take journal",
      "west",
      "north",
      "north",
      "take orb",
      "north",
      "east",
      "east",
      "north",
      "west",
      "south",
      "east",
      "east",
      "west",
      "north",
      "north",
      "east",
      "vault",
      "take mirror",
      "use mirror"
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
      items -> label <> "\n\n\nItem: " <> item_strs(items)
    end
    {node_id, _} = Node.new(label: label)
    if @default_start_offset == offset do
      Node.update(node_id, color: "green")
    end
    %Room{room | node_id: node_id}
  end

  defp item_strs(item_list) do
    item_list
    |> Enum.map(&item_str/1)
    |> Enum.join("\n\n")
  end

  defp item_str(item) do
    desc = String.replace("#{item.description}", ~s("), ~s('))
    name = String.replace("#{item.name}", ~s("), ~s('))
    "#{name} (#{inspect item.offset})\n#{desc}"
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
    new_map = Map.update(acc, item.location, [item], &([item] ++ &1))
    read_next_item(num_items - 1, offset + 1, bin, new_map)
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

  @encrypted_strings [
    {26851, 16353+5658},
    {27414, 7734+9395},
    {27432, 4595+2160},
    {27455, 23069+8535},
    {27482, 8104+8912},
    {27532, 4592+25603},
    {28037, 432+1484},
    {28054, 238+5885},
    {28062, 20833+2578},
    {28090, 1769+14212},
    {28100, 27093+5662},
    {28135, 17703+10555},
    {28170, 4307+2452},
    {28204, 11030+2765},
    {28236, 2352+5191},
    {28303, 2891+21801},
    {28347, 286+338},
    {28369, 10605+12156},
    {28401, 16785+8685},
    {28453, 11174+5819},
    {28510, 53+74},
    {28569, 898+100},
    {28595, 3585+6892},
    {28621, 14379+13501},
    {28664, 271+13145},
    {28679, 1298+9300},
    {28710, 6071+23493},
    {28777, 2876+15154},
    {28844, 1475+12831},
    {29014, 9025+690},
    {29245, 16808+10433},
    {29400, 25133+3901},
    {29545, 8342+18380},
    {29667, 26729+1158},
    {29757, 28931+3696},
    {29946, 14595+4719}
    ]

  @doc """
  Decrypt all encrypted strings in the instructions
  """
  def decrypt_all_strings(instructions) do
    for {offset, key} <- @encrypted_strings do
      str = decrypt(offset, key, instructions)
      IO.puts "#{IO.ANSI.bright()}[#{inspect offset}]#{IO.ANSI.reset()} : #{inspect str}"
    end
    :ok
  end

  @doc """
  Decrypt strings
  """
  def decrypt(offset, key, instructions) do
    cnt = Token.get_value(offset, instructions)
    decrypt_list(cnt, offset, key, instructions, [])
  end

  defp decrypt_list(0, _, _, _, acc), do: acc
  defp decrypt_list(cnt, offset, key, instructions, acc) do
    token = Token.get_value(offset + cnt, instructions)
    decrypted = decrypt_value(token, key)
    decrypt_list(cnt - 1, offset, key, instructions, [decrypted | acc])
  end

  defp decrypt_value(val, key) do
    r2 = band(val, key)
    r2 = flip_bits(r2)
    r0 = bor(val, key)
    r0 = band(r0, r2)
    r0
  end

  defp flip_bits(bin) do
    <<l::integer-size(15)>> = for <<c::size(1) <- <<bin::integer-size(15)>> >>, into: <<>>, do: flip_bit(c)
    l
  end

  defp flip_bit(1), do: <<0::size(1)>>
  defp flip_bit(0), do: <<1::size(1)>>


  # [06027]  {:jt, {:reg, 0}, {:value, 6035}}                      if r0 goto 6035
  # [06030]  {:add, {:reg, 0}, {:reg, 1}, {:value, 1}}             else r0 = r1+1
  # [06034]  {:ret}                                                return
  #
  # [06035]  {:jt, {:reg, 1}, {:value, 6048}}                      if r1 goto 6048
  # [06038]  {:add, {:reg, 0}, {:reg, 0}, {:value, 32767}}         else r0 = r0 + 32767
  # [06042]  {:set, {:reg, 1}, {:reg, 7}}                          r1 = r7
  # [06045]  {:call, {:value, 6027}}                               call 6027
  # [06047]  {:ret}                                                return
  #
  # [06048]  {:push, {:reg, 0}}                                    store r0
  # [06050]  {:add, {:reg, 1}, {:reg, 1}, {:value, 32767}}         r1 = r1 + 32767
  # [06054]  {:call, {:value, 6027}}                               call 6027
  # [06056]  {:set, {:reg, 1}, {:reg, 0}}                          r1 = r0
  # [06059]  {:pop, {:reg, 0}}                                     restore r0
  # [06061]  {:add, {:reg, 0}, {:reg, 0}, {:value, 32767}}         r0 = r0 + 32767
  # [06065]  {:call, {:value, 6027}}                               call 6027
  # [06067]  {:ret}                                                return


  # [05483]  {:set, {:reg, 0}, {:value, 4}}				# args for ackerman(4, 1)
  # [05486]  {:set, {:reg, 1}, {:value, 1}}
  # [05489]  {:call, {:value, 6027}}				# Call teleporter ackermann function
  # [05491]  {:eq, {:reg, 1}, {:reg, 0}, {:value, 6}}				# R0 must be 6 to pass confirmation check
  # [05495]  {:jf, {:reg, 1}, {:value, 5579}}

  @doc """
  Search for the right value of r7 to make the function return 6

  r0 = 4, r1 = 1, r7 = ?
  Select r7 such that r0 = 6
  Found r7 = 25734
  """
  def teleport_search do
    for r7 <- 0..32767 do
      result = teleport_confirmation(4, 1, r7)
      if 6 == result do
        IO.puts "Found teleport(4, 1, #{inspect r7}) = #{inspect result}"
      end
    end
  end

  @doc """
  Implementation of teleport confirmation algorithm
  """
  def teleport_confirmation(r0, r1, r7) do
    one(r0, r1, r7)
  end

  @range 32768

  defp one(0, r1, _), do: Integer.mod(r1 + 1, @range)
  defp one(1, r1, r7), do: Integer.mod(r1 + 2 + (r7 - 1), @range)
  defp one(2, r1, r7), do: Integer.mod((r1 + 1) + (r7 * (r1 + 2)), @range)
  defp one(r0, r1, r7) do
    two(r0, r1, r7)
  end

  defp two(r0, 0, r7) do
    r0 = Integer.mod(r0 + (@range - 1), @range) # r0 = r0 - 1
    r1 = r7
    one(r0, r1, r7)
  end
  defp two(r0, r1, r7), do: three(r0, r1, r7)

  defp three(r0, r1, r7) do
    r1 = Integer.mod(r1 + (@range - 1), @range) # r1 = r1 - 1
    r1 = one(r0, r1, r7)
    r0 = Integer.mod(r0 + (@range - 1), @range) # r0 = r0 - 1
    one(r0, r1, r7)
  end

  # Vault lock room map
  @vault %{
    2623 => %{directions: [east: 2628, north: 2603], action: nil, value: 22},
    2628 => %{directions: [north: 2608, east: 2633], action: :-, value: nil},
    2608 => %{directions: [south: 2628, north: 2588, east: 2613, west: 2603], action: nil, value: 4},
    2588 => %{directions: [south: 2608, north: 2568, east: 2593, west: 2583], action: :*, value: nil},
    2568 => %{directions: [south: 2588, east: 2573, west: 2563], action: nil, value: 8},
    2563 => %{directions: [east: 2568, south: 2583], action: :*, value: nil},
    2583 => %{directions: [north: 2563, south: 2603, east: 2588], action: nil, value: 4},
    2603 => %{directions: [north: 2583, east: 2608], action: :+, value: nil},
    2573 => %{directions: [west: 2568, south: 2593, east: 2578], action: :-, value: nil},
    2593 => %{directions: [north: 2573, south: 2613, east: 2598, west: 2588], action: nil, value: 11},
    2613 => %{directions: [north: 2593, south: 2633, east: 2618, west: 2608], action: :-, value: nil},
    2633 => %{directions: [north: 2613, east: 2638, west: 2628], action: nil, value: 9},
    2638 => %{directions: [west: 2633, north: 2618], action: :*, value: nil},
    2618 => %{directions: [south: 2638, north: 2598, west: 2613], action: nil, value: 18},
    2598 => %{directions: [south: 2618, north: 2578, west: 2593], action: :*, value: nil},
    2578 => %{directions: [], action: nil, value: 1}
  }

  @vault_start 2623
  @vault_end 2578
  @vault_target 30
  @max_path 13

  @doc """
  Search the vault lock rooms
  """
  def search_vault do
    visit_room(@vault_start, [], MapSet.new, {0, :+})
  end

  defp visit_room(room_id = @vault_end, path, _visited, state) do
    room = Map.get(@vault, room_id)
    {value, _action} = evaluate(state, room.action, room.value)
    # IO.puts "In final room, value = #{inspect value}"
    if @vault_target == value do
      IO.puts "Found path, length: #{length(path)}: #{inspect Enum.reverse(path)}"
      # {true, Enum.reverse(path)}
      {false, nil}
    else
      {false, nil}
    end
  end
  defp visit_room(room_id, path, visited, state) do
    room = Map.get(@vault, room_id)
    # IO.puts "Visiting room: #{inspect room_id} {#{inspect room.value}, #{inspect room.action}} , Path: #{inspect path}, State: #{inspect state}"
    new_state = evaluate(state, room.action, room.value)
    visit_neighbors(room_id, room.directions, path, MapSet.put(visited, room_id), new_state)
  end

  defp visit_neighbors(_room_id, [], _path, _visited, _new_state) do
    # IO.puts "#{inspect room_id}: no more neighbors"
    {false, nil}
  end
  defp visit_neighbors(room_id, [{dir, neighbor_id} | rest], path, visited, state) do
    if length(path) >= @max_path do
      # IO.puts "#{inspect neighbor_id}: already visited"
      # visit_neighbors(room_id, rest, path, visited, state)
      {false, nil}
    else
      # IO.puts "Going #{inspect dir}"
      case visit_room(neighbor_id, [dir | path], visited, state) do
        {true, path} -> {true, path}
        {false, nil} -> visit_neighbors(room_id, rest, path, visited, state)
      end
    end
  end

  defp evaluate({value, _action}, new_action, nil), do: {value, new_action}
  defp evaluate({value, :+}, nil, new_value), do: {Integer.mod(value + new_value, @range), nil}
  defp evaluate({value, :-}, nil, new_value), do: {Integer.mod(value - new_value, @range), nil}
  defp evaluate({value, :*}, nil, new_value), do: {Integer.mod(value * new_value, @range), nil}

end
