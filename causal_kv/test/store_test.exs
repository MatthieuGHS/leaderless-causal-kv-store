defmodule CausalKv.StoreTest do
  use ExUnit.Case
  alias CausalKv.Store

  test "leq? compare composante par composante" do
    assert Store.leq?(%{1 => 1, 2 => 0}, %{1 => 1, 2 => 2})
    refute Store.leq?(%{1 => 2, 2 => 0}, %{1 => 1, 2 => 2})
  end

  test "lt? compare composante par composante" do
    assert Store.lt?(%{1 => 1, 2 => 0}, %{1 => 1, 2 => 2})
    refute Store.lt?(%{1 => 2, 2 => 0}, %{1 => 1, 2 => 2})
  end

  test "concurrent? compare composante par composante" do
    assert Store.concurrent?(%{1 => 1, 2 => 0}, %{1 => 0, 2 => 2})
    refute Store.concurrent?(%{1 => 1, 2 => 0}, %{1 => 1, 2 => 2})
  end

  test "vecteurs égaux" do
    a = %{1 => 1, 2 => 0}
    assert Store.leq?(a, a)
    refute Store.lt?(a, a)
    refute Store.concurrent?(a, a)
  end

  test "apply_write : écrasement normal" do
    stocke = [{1, %{1 => 1, 2 => 0, 3 => 0}}]
    resultat = Store.apply_write(stocke, {2, %{1 => 2, 2 => 0, 3 => 0}})
    assert resultat == [{2, %{1 => 2, 2 => 0, 3 => 0}}]
  end

  test "apply_write : siblings" do
    stocke = [{1, %{1 => 0, 2 => 1, 3 => 0}}]
    resultat = Store.apply_write(stocke, {2, %{1 => 1, 2 => 0, 3 => 0}})

    assert MapSet.new(resultat) ==
             MapSet.new([{2, %{1 => 1, 2 => 0, 3 => 0}}, {1, %{1 => 0, 2 => 1, 3 => 0}}])
  end

  test "apply_write : fusion" do
    stocke = [{1, %{1 => 0, 2 => 1, 3 => 0}}, {2, %{1 => 1, 2 => 0, 3 => 0}}]
    resultat = Store.apply_write(stocke, {3, %{1 => 1, 2 => 1, 3 => 1}})
    assert resultat == [{3, %{1 => 1, 2 => 1, 3 => 1}}]
  end

  test "version : incrémentation" do
    cp = %{1 => 1, 2 => 0, 3 => 0}
    assert Store.version(cp, 1) == %{1 => 2, 2 => 0, 3 => 0}
    assert Store.version(cp, 2) == %{1 => 1, 2 => 1, 3 => 0}
    assert Store.version(cp, 3) == %{1 => 1, 2 => 0, 3 => 1}
  end
end
