defmodule SynacorTest.Maze do
  use ExUnit.Case
  doctest Synacor.Maze
  alias Synacor.Maze

  test "normal ackermann" do
    assert 1 == Maze.teleport_confirmation(0, 0, 1)
    assert 5 == Maze.teleport_confirmation(0, 4, 1)
    assert 3 == Maze.teleport_confirmation(1, 1, 1)
    assert 6 == Maze.teleport_confirmation(1, 4, 1)
    assert 5 == Maze.teleport_confirmation(2, 1, 1)
    assert 9 == Maze.teleport_confirmation(2, 3, 1)
    assert 13 == Maze.teleport_confirmation(4, 0, 1)
    assert 32765 == Maze.teleport_confirmation(4, 1, 1)
  end

end
