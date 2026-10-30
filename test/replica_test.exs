defmodule CausalKv.ReplicaTest do
  use ExUnit.Case
  alias CausalKv.Replica

  test "get sur une clé inconnue renvoie []" do
    r = start_supervised!({Replica, 1})
    assert Replica.get(r, :x) == []
  end

  test "put puis get renvoie la valeur" do
    r = start_supervised!({Replica, 1})
    assert Replica.put(r, :x, 1) == :ok
    assert Replica.get(r, :x) == [1]
  end

  test "deux put successifs : seule la dernière valeur reste" do
    r = start_supervised!({Replica, 1})
    Replica.put(r, :x, 1)
    Replica.put(r, :x, 2)
    assert Replica.get(r, :x) == [2]
  end

  test "le cp avance de 1 à chaque put" do
    r = start_supervised!({Replica, 1})
    Replica.put(r, :x, 1)
    Replica.put(r, :y, 2)
    assert :sys.get_state(r).cp == %{1 => 2, 2 => 0, 3 => 0}
  end

  test "le vecteur stocké est celui de l'écriture" do
    r = start_supervised!({Replica, 1})
    Replica.put(r, :x, 1)
    assert :sys.get_state(r).store == %{x: [{1, %{1 => 1, 2 => 0, 3 => 0}}]}
  end

  test "un put sur :x ne touche pas :y" do
    r = start_supervised!({Replica, 1})
    Replica.put(r, :x, 1)
    Replica.put(r, :y, 2)
    Replica.put(r, :x, 3)
    assert Replica.get(r, :x) == [3]
    assert Replica.get(r, :y) == [2]
  end

  test "une réplique d'id 2 incrémente sa propre case" do
    r = start_supervised!({Replica, 2})
    Replica.put(r, :x, 1)
    assert :sys.get_state(r).cp == %{1 => 0, 2 => 1, 3 => 0}
  end

  test "une écriture sur R1 arrive sur R2 et R3" do
    r1 = start_supervised!({Replica, 1}, id: :r1)
    r2 = start_supervised!({Replica, 2}, id: :r2)
    r3 = start_supervised!({Replica, 3}, id: :r3)

    Replica.put(r1, :x, 1)
    Process.sleep(50)

    assert Replica.get(r2, :x) == [1]
    assert Replica.get(r3, :x) == [1]
    assert :sys.get_state(r2).cp == %{1 => 1, 2 => 0, 3 => 0}
  end
end
