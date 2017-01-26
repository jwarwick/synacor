defmodule SynacorTest.Maze do
  use ExUnit.Case
  doctest Synacor.Maze
  alias Synacor.Maze

  test "normal ackermann" do
    assert 1 == Maze.teleport_confirmation(0, 0, 1)
    assert 5 == Maze.teleport_confirmation(0, 4, 1)
    assert 3 == Maze.teleport_confirmation(1, 1, 1)
    assert 6 == Maze.teleport_confirmation(1, 4, 1)
    assert 3 == Maze.teleport_confirmation(2, 0, 1)
    assert 5 == Maze.teleport_confirmation(2, 1, 1)
    assert 7 == Maze.teleport_confirmation(2, 2, 1)
    assert 9 == Maze.teleport_confirmation(2, 3, 1)
    assert 13 == Maze.teleport_confirmation(4, 0, 1)
    assert 32765 == Maze.teleport_confirmation(4, 1, 1)
  end

  test "modified ackermann" do
    assert 1 == Maze.teleport_confirmation(0, 0, 0)
    assert 1 == Maze.teleport_confirmation(0, 0, 2)
    assert 3 == Maze.teleport_confirmation(1, 0, 2)
    assert 4 == Maze.teleport_confirmation(1, 1, 2)
    assert 7 == Maze.teleport_confirmation(1, 4, 2)
    assert 12 == Maze.teleport_confirmation(1, 3, 8)
    assert 8 == Maze.teleport_confirmation(2, 1, 2)
    assert 15 == Maze.teleport_confirmation(2, 2, 3)
    assert 5 == Maze.teleport_confirmation(2, 4, 0)
  end

end
