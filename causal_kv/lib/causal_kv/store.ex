defmodule CausalKv.Store do
  @moduledoc """
  Vecteurs de version et règle d'application des écritures.
  """

  @doc "a <= b : chaque composante de a est inférieure ou égale à celle de b."

  def leq?(a, b) do
    Enum.all?(a, fn {k, x} -> x <= Map.get(b, k, 0) end)
  end

  def lt?(a, b) do
    leq?(a, b) and a != b
  end

  def concurrent?(a, b) do
    not leq?(a, b) and not leq?(b, a)
  end

  def apply_write(versions, {v, vec}) do
    [{v, vec} | Enum.filter(versions, fn {_, v2} -> not lt?(v2, vec) end)]
  end

  def version(cp, sender) do
    Map.update!(cp, sender, fn x -> x + 1 end)
  end
end
