defmodule Emergencias.Servidores.Albergues do
  @moduledoc """
  GenServer de albergues. El ingreso de personas verifica capacidad y registra
  al ocupante en un solo `handle_call`, de modo que dos ingresos simultáneos
  nunca dejan la ocupación por encima de la capacidad máxima.
  """

  use GenServer

  alias Emergencias.Persistencia
  alias Emergencias.Dominio.Albergue

  @archivo "albergues.txt"

  # ---------------------------------------------------------------------------
  # API
  # ---------------------------------------------------------------------------

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  def registrar(attrs), do: GenServer.call(__MODULE__, {:registrar, attrs})
  def obtener(codigo), do: GenServer.call(__MODULE__, {:obtener, codigo})
  def existe?(codigo), do: match?({:ok, _}, obtener(codigo))
  def listar, do: GenServer.call(__MODULE__, :listar)
  def ingresar(codigo, documento), do: GenServer.call(__MODULE__, {:ingresar, codigo, documento})
  def salir(codigo, documento), do: GenServer.call(__MODULE__, {:salir, codigo, documento})

  @doc "Albergues que todavía tienen cupo, de más a menos cupos."
  def disponibles, do: GenServer.call(__MODULE__, :disponibles)

  @doc "Ranking de los `n` albergues con mayor porcentaje de ocupación."
  def ranking(n \\ 5), do: GenServer.call(__MODULE__, {:ranking, n})

  def reiniciar, do: GenServer.call(__MODULE__, :reiniciar)

  # ---------------------------------------------------------------------------
  # Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(:ok) do
    albergues =
      @archivo
      |> Persistencia.leer()
      |> Map.new(fn fila ->
        albergue = Albergue.desde_fila(fila)
        {albergue.codigo, albergue}
      end)

    {:ok, albergues}
  end

  @impl true
  def handle_call({:registrar, attrs}, _de, albergues) do
    with {:ok, albergue} <- Albergue.nuevo(attrs),
         :ok <- no_duplicado(albergues, albergue.codigo) do
      {:reply, {:ok, albergue}, poner(albergues, albergue)}
    else
      error -> {:reply, error, albergues}
    end
  end

  def handle_call({:obtener, codigo}, _de, albergues),
    do: {:reply, buscar(albergues, codigo), albergues}

  def handle_call(:listar, _de, albergues),
    do: {:reply, albergues |> Map.values() |> Enum.sort_by(& &1.codigo), albergues}

  def handle_call({:ingresar, codigo, documento}, _de, albergues) do
    with {:ok, albergue} <- buscar(albergues, codigo),
         :ok <- no_esta_en_otro(albergues, codigo, documento),
         {:ok, actualizado} <- Albergue.ingresar(albergue, documento) do
      {:reply, {:ok, actualizado}, poner(albergues, actualizado)}
    else
      error -> {:reply, error, albergues}
    end
  end

  def handle_call({:salir, codigo, documento}, _de, albergues) do
    with {:ok, albergue} <- buscar(albergues, codigo),
         {:ok, actualizado} <- Albergue.salir(albergue, documento) do
      {:reply, {:ok, actualizado}, poner(albergues, actualizado)}
    else
      error -> {:reply, error, albergues}
    end
  end

  def handle_call(:disponibles, _de, albergues) do
    lista =
      albergues
      |> Map.values()
      |> Enum.filter(&(Albergue.cupos(&1) > 0))
      |> Enum.sort_by(&(-Albergue.cupos(&1)))

    {:reply, lista, albergues}
  end

  def handle_call({:ranking, n}, _de, albergues),
    do: {:reply, albergues |> Map.values() |> Albergue.top(n), albergues}

  def handle_call(:reiniciar, _de, _albergues) do
    Persistencia.eliminar(@archivo)
    {:reply, :ok, %{}}
  end

  # ---------------------------------------------------------------------------
  # Auxiliares
  # ---------------------------------------------------------------------------

  defp buscar(albergues, codigo) do
    case Map.fetch(albergues, codigo) do
      {:ok, albergue} -> {:ok, albergue}
      :error -> {:error, {:no_encontrado, codigo}}
    end
  end

  defp no_duplicado(albergues, codigo) do
    if Map.has_key?(albergues, codigo), do: {:error, {:id_duplicado, codigo}}, else: :ok
  end

  # Una persona no puede estar registrada en dos albergues a la vez.
  defp no_esta_en_otro(albergues, codigo, documento) do
    case Enum.find(
           Map.values(albergues),
           &(&1.codigo != codigo and MapSet.member?(&1.ocupantes, documento))
         ) do
      nil -> :ok
      otro -> {:error, {:ya_esta_en_otro_albergue, otro.codigo}}
    end
  end

  defp poner(albergues, albergue) do
    nuevos = Map.put(albergues, albergue.codigo, albergue)
    Persistencia.guardar(@archivo, nuevos |> Map.values() |> Enum.map(&Albergue.a_fila/1))
    nuevos
  end
end
