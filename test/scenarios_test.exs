defmodule CausalKv.ScenariosTest do
  use ExUnit.Case
  alias CausalKv.{Replica, Net}

  setup do
    Net.clear()
    :ok
  end

  # démarre R1, R2, R3 dans le mode donné, renvoie [r1, r2, r3]
  defp start_replicas(mode) do
    for i <- 1..3 do
      start_supervised!({Replica, id: i, mode: mode}, id: :"r#{i}")
    end
  end

  # ------------------------------------------------------------------
  # Scénario 1 : R1 crashe au milieu de sa diffusion (URB / Termination 2)
  # ------------------------------------------------------------------
  defp crash_scenario(mode) do
    [r1, r2, r3] = start_replicas(mode)
    # R1 n'a pas eu le temps d'envoyer à R3…
    Net.set(1, 3, :drop)
    Replica.put(r1, :x, 1)
    # …et crashe
    stop_supervised(:r1)
    Process.sleep(100)
    {r2, r3}
  end

  test "naïf : si l'émetteur crashe, R3 ne reçoit jamais l'écriture" do
    {r2, r3} = crash_scenario(:naive)
    assert Replica.get(r2, :x) == [1]
    # divergence définitive
    assert Replica.get(r3, :x) == []
  end

  test "CO-URB : R2 relaie, R3 reçoit quand même l'écriture" do
    {r2, r3} = crash_scenario(:co)
    assert Replica.get(r2, :x) == [1]
    assert Replica.get(r3, :x) == [1]
  end

  # ------------------------------------------------------------------
  # Scénario 2 : question / réponse (ordre causal, DDIA fig. 6-8)
  # ------------------------------------------------------------------
  # R1 écrit la question, R2 la lit puis écrit la réponse.
  # Tout ce qui va vers R3 avec la question est lent ; la réponse arrive vite.
  defp qa_scenario(mode) do
    [r1, r2, r3] = start_replicas(mode)
    Net.set(1, 3, 300)
    # retarde aussi le relais de la question par R2
    Net.set(2, 3, 300)

    Replica.put(r1, :q, "question?")
    # R2 a reçu la question
    Process.sleep(50)
    # à partir de maintenant, R2 → R3 est rapide
    Net.set(2, 3, 0)
    # la réponse dépend causalement de la question
    Replica.put(r2, :a, "réponse!")

    # la réponse est arrivée sur R3, pas la question
    Process.sleep(50)

    mid = %{
      q: Replica.get(r3, :q),
      a: Replica.get(r3, :a),
      pending: length(:sys.get_state(r3).pending)
    }

    # tout est arrivé
    Process.sleep(500)
    {mid, :sys.get_state(r3).log}
  end

  test "naïf : R3 voit la réponse avant la question" do
    {mid, log} = qa_scenario(:naive)
    assert mid.a == ["réponse!"]
    # anomalie : réponse sans question
    assert mid.q == []
    # ordre causal violé
    assert log == [{2, 1}, {1, 1}]
  end

  test "CO-URB : R3 met la réponse en attente jusqu'à la question" do
    {mid, log} = qa_scenario(:co)
    # réponse bloquée…
    assert mid.a == []
    assert mid.q == []
    # …dans pending
    assert mid.pending == 1
    # ordre causal respecté
    assert log == [{1, 1}, {2, 1}]
  end

  # ------------------------------------------------------------------
  # Scénario 3 : écritures concurrentes → siblings, puis merge
  # ------------------------------------------------------------------
  test "deux put concurrents donnent des siblings partout, un put suivant les fusionne" do
    [r1, r2, r3] = start_replicas(:co)

    # R1 et R2 ne doivent rien recevoir l'un de l'autre avant d'écrire
    for {from, to} <- [{1, 2}, {3, 2}, {2, 1}, {3, 1}], do: Net.set(from, to, 200)

    Replica.put(r1, :x, "a")
    Replica.put(r2, :x, "b")
    Process.sleep(400)

    for r <- [r1, r2, r3] do
      assert Enum.sort(Replica.get(r, :x)) == ["a", "b"]
    end

    # le client lit les siblings sur R1 et écrit une valeur fusionnée
    Net.clear()
    Replica.put(r1, :x, "ab")
    Process.sleep(50)

    for r <- [r1, r2, r3] do
      assert Replica.get(r, :x) == ["ab"]
    end
  end
end
