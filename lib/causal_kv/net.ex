defmodule CausalKv.Net do
  @key {__MODULE__, :rules}

  def rules, do: :persistent_term.get(@key, %{})
  def clear, do: :persistent_term.put(@key, %{})

  def set(from, to, rule) do
    :persistent_term.put(@key, Map.put(rules(), {from, to}, rule))
  end

  def send(from, to, msg) do
    dest = CausalKv.Replica.name(to)

    case Map.get(rules(), {from, to}) do
      nil   -> GenServer.cast(dest, msg)   # cast directly
      :drop -> :ok                         # message lost
      ms    -> spawn(fn ->
                  Process.sleep(ms)
                  GenServer.cast(dest, msg)
                end)
    end
  end
end
