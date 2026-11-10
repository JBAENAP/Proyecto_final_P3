defmodule Emergencias.Servidores.Zonas do
  @moduledoc """
  GenServer dueño del árbol zona → sectores → puntos de atención.
  El estado es la lista de zonas raíz (cada una con sus hijos anidados).
  """

  use GenServer

  alias Emergencias.Persistencia
  alias Emergencias.Dominio.Zona

  @archivo "zonas.txt"

  # ---------------------------------------------------------------------------
  # API
  # ---------------------------------------------------------------------------

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  def registrar_zona(codigo, nombre, nivel, personas),
    do:
      GenServer.call(
        __MODULE__,
        {:registrar, nil, Zona.nuevo(:zona, codigo, nombre, nivel, personas)}
      )

  def registrar_sector(zona, codigo, nombre, nivel, personas),
    do:
      GenServer.call(
        __MODULE__,
        {:registrar, zona, Zona.nuevo(:sector, codigo, nombre, nivel, personas)}
      )

  def registrar_punto(sector, codigo, nombre, categoria, personas \\ 0),
    do:
      GenServer.call(
        __MODULE__,
        {:registrar, sector, Zona.nuevo(:punto, codigo, nombre, nil, personas, categoria)}
      )

  @doc "Actualiza nivel de afectación y/o personas estimadas de un nodo."
  def actualizar(codigo, cambios), do: GenServer.call(__MODULE__, {:actualizar, codigo, cambios})

  def obtener(codigo), do: GenServer.call(__MODULE__, {:obtener, codigo})
  def arbol, do: GenServer.call(__MODULE__, :arbol)
  def existe?(codigo), do: match?({:ok, _}, obtener(codigo))
  def raiz(codigo), do: GenServer.call(__MODULE__, {:raiz, codigo})
  def reiniciar, do: GenServer.call(__MODULE__, :reiniciar)

  @doc "Mapa `codigo => codigo_raiz` de todos los nodos (lo usa el algoritmo de mascotas)."
  def mapa_raices, do: GenServer.call(__MODULE__, :mapa_raices)

  # ---------------------------------------------------------------------------
  # Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(:ok), do: {:ok, @archivo |> Persistencia.leer() |> Zona.desde_filas()}

  @impl true
  def handle_call({:registrar, _padre, {:error, _} = error}, _de, arbol),
    do: {:reply, error, arbol}

  def handle_call({:registrar, padre, {:ok, nodo}}, _de, arbol) do
    resultado =
      cond do
        Zona.buscar(arbol, nodo.codigo) -> {:error, {:id_duplicado, nodo.codigo}}
        padre == nil -> {:ok, arbol ++ [nodo]}
        true -> Zona.insertar(arbol, padre, nodo)
      end

    case resultado do
      {:ok, nuevo} ->
        guardar(nuevo)
        {:reply, {:ok, nodo}, nuevo}

      error ->
        {:reply, error, arbol}
    end
  end

  def handle_call({:actualizar, codigo, cambios}, _de, arbol) do
    case Zona.actualizar(arbol, codigo, &struct(&1, cambios)) do
      {:ok, nuevo} ->
        guardar(nuevo)
        {:reply, {:ok, Zona.buscar(nuevo, codigo)}, nuevo}

      :no_encontrado ->
        {:reply, {:error, {:no_encontrado, codigo}}, arbol}
    end
  end

  def handle_call({:obtener, codigo}, _de, arbol) do
    case Zona.buscar(arbol, codigo) do
      nil -> {:reply, {:error, {:no_encontrado, codigo}}, arbol}
      nodo -> {:reply, {:ok, nodo}, arbol}
    end
  end

  def handle_call({:raiz, codigo}, _de, arbol), do: {:reply, Zona.raiz(arbol, codigo), arbol}
  def handle_call(:arbol, _de, arbol), do: {:reply, arbol, arbol}

  def handle_call(:mapa_raices, _de, arbol) do
    mapa =
      Enum.reduce(arbol, %{}, fn raiz, acc ->
        raiz |> Zona.codigos() |> Map.new(&{&1, raiz.codigo}) |> Map.merge(acc)
      end)

    {:reply, mapa, arbol}
  end

  def handle_call(:reiniciar, _de, _arbol) do
    Persistencia.eliminar(@archivo)
    {:reply, :ok, []}
  end

  defp guardar(arbol), do: Persistencia.guardar(@archivo, Zona.a_filas(arbol))
end
