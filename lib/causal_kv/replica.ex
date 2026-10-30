defmodule CausalKv.Replica do
  use GenServer

  # ---------- API client ----------

  def name(id), do: :"replica_#{id}"
  def start_link(id), do: GenServer.start_link(__MODULE__, id, name: name(id))

  def get(pid, key) do
    GenServer.call(pid, {:get, key})
  end

  def put(pid, key, value) do
    GenServer.call(pid, {:put, key, value})
  end

  # ---------- Callbacks ----------

  @impl true
  def init(id) do
    state = %{
      id: id,
      seen: MapSet.new(),
      pending: [],
      cp: %{1 => 0, 2 => 0, 3 => 0},
      store: %{}
    }

    {:ok, state}
  end

  defp send_others(state, msg) do
    for j <- [1, 2, 3], j != state.id do
      GenServer.cast(name(j), {:urb, msg})
    end
  end

  @impl true
  def handle_call({:get, key}, _from, state) do
    versions = Map.get(state.store, key, [])
    {:reply, Enum.map(versions, fn {v, _} -> v end), state}
  end

  @impl true
  def handle_call({:put, key, value}, _from, state) do
    m = %{id: {state.id, state.cp[state.id] + 1}, sender: state.id, cp: state.cp, key: key, value: value}
    state = Map.update!(state, :seen, fn seen -> MapSet.put(seen, m.id) end)
    send_others(state, m)
    state = deliver(state, m)
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:urb, m}, state) do
    if MapSet.member?(state.seen, m.id) do
      {:noreply, state}
    else
      state = Map.update!(state, :seen, fn seen -> MapSet.put(seen, m.id) end)
      send_others(state, m)
      state = Map.update!(state, :pending, fn pending -> [m | pending] end)
      {:noreply, try_deliver(state)}
    end
  end

  defp deliver(state, m) do
    vec = CausalKv.Store.version(m.cp, m.sender)
    cp  = Map.update!(state.cp, m.sender, fn x -> x + 1 end)
    versions = CausalKv.Store.apply_write(Map.get(state.store, m.key, []), {m.value, vec})
    %{state | cp: cp, store: Map.put(state.store, m.key, versions)}
  end

  defp try_deliver(state) do
    case Enum.find(state.pending, fn m -> CausalKv.Store.leq?(m.cp, state.cp) end) do
      nil -> state
      m ->
        state = %{state | pending: List.delete(state.pending, m)}
        state = deliver(state, m)
        try_deliver(state)
    end
  end

end
