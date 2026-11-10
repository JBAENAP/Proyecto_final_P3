defmodule Emergencias.Servidores.Necesidades do
  @moduledoc """
  GenServer dueño de las necesidades puntuales.

  Al asignar recursos, este proceso valida la necesidad y luego le pide el retiro
  al `Inventario`. La dependencia es en una sola dirección (Necesidades → Inventario,
  nunca al revés), por lo que no hay riesgo de bloqueo mutuo. Como las asignaciones
  de una misma necesidad también se serializan aquí, una necesidad atendida o
  cancelada nunca vuelve a consumir recursos y nunca se sobre-asigna.
  """

  use GenServer

  alias Emergencias.Persistencia
  alias Emergencias.Dominio.Necesidad
  alias Emergencias.Servidores.Inventario

  @archivo "necesidades.txt"

  # ---------------------------------------------------------------------------
  # API
  # ---------------------------------------------------------------------------

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  def registrar(attrs), do: GenServer.call(__MODULE__, {:registrar, attrs})
  def obtener(id), do: GenServer.call(__MODULE__, {:obtener, normalizar_id(id)})
  def listar(filtros \\ %{}), do: GenServer.call(__MODULE__, {:listar, filtros})

  @doc "Asigna `cantidad` unidades de recursos de `tipo` a la necesidad `id`."
  def asignar(id, tipo, cantidad, usuario, opciones \\ []),
    do:
      GenServer.call(__MODULE__, {:asignar, normalizar_id(id), tipo, cantidad, usuario, opciones})

  def cambiar_estado(id, estado),
    do: GenServer.call(__MODULE__, {:cambiar_estado, normalizar_id(id), estado})

  @doc "Recorre las necesidades abiertas por prioridad y les entrega lo disponible."
  def despachar(usuario), do: GenServer.call(__MODULE__, {:despachar, usuario}, 30_000)

  def reiniciar, do: GenServer.call(__MODULE__, :reiniciar)

  def normalizar_id(id) when is_binary(id), do: id |> String.trim() |> String.upcase()
  def normalizar_id(id), do: id

  # ---------------------------------------------------------------------------
  # Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(:ok) do
    necesidades =
      @archivo
      |> Persistencia.leer()
      |> Map.new(fn fila ->
        necesidad = Necesidad.desde_fila(fila)
        {necesidad.id, necesidad}
      end)

    {:ok, %{necesidades: necesidades, siguiente: siguiente_numero(necesidades)}}
  end

  @impl true
  def handle_call({:registrar, attrs}, _de, estado) do
    id = "N" <> String.pad_leading(Integer.to_string(estado.siguiente), 3, "0")

    case Necesidad.nueva(id, attrs) do
      {:ok, necesidad} ->
        nuevo = %{estado | siguiente: estado.siguiente + 1} |> poner(necesidad)
        {:reply, {:ok, necesidad}, nuevo}

      error ->
        {:reply, error, estado}
    end
  end

  def handle_call({:obtener, id}, _de, estado), do: {:reply, buscar(estado, id), estado}

  def handle_call({:listar, filtros}, _de, estado) do
    lista =
      estado.necesidades |> Map.values() |> Necesidad.filtrar(filtros) |> Necesidad.ordenar()

    {:reply, lista, estado}
  end

  def handle_call({:asignar, id, tipo, cantidad, usuario, opciones}, _de, estado) do
    case asignar_interno(estado, id, tipo, cantidad, usuario, opciones) do
      {:ok, necesidad, plan, nuevo} -> {:reply, {:ok, necesidad, plan}, nuevo}
      error -> {:reply, error, estado}
    end
  end

  def handle_call({:cambiar_estado, id, nuevo_estado}, _de, estado) do
    with {:ok, necesidad} <- buscar(estado, id),
         {:ok, actualizada} <- Necesidad.cambiar_estado(necesidad, nuevo_estado) do
      {:reply, {:ok, actualizada}, poner(estado, actualizada)}
    else
      error -> {:reply, error, estado}
    end
  end

  def handle_call({:despachar, usuario}, _de, estado) do
    abiertas =
      estado.necesidades
      |> Map.values()
      |> Enum.filter(&(Necesidad.abierta?(&1) and Necesidad.faltante(&1) > 0))
      |> Necesidad.ordenar()

    # La función que se pasa a la recursión entrega lo que haya disponible
    # (retiro parcial) del tipo de la necesidad.
    asignar = fn necesidad ->
      opciones = [parcial: true, preferir: [necesidad.zona]]

      with {:ok, plan} <-
             retirar(necesidad, necesidad.tipo, Necesidad.faltante(necesidad), usuario, opciones) do
        {:ok, Necesidad.registrar_asignacion(necesidad, plan), plan}
      end
    end

    resultados = Necesidad.despachar(abiertas, asignar, [])

    nuevo =
      Enum.reduce(resultados, estado, fn
        {:asignada, necesidad, _plan}, acc -> poner(acc, necesidad)
        _, acc -> acc
      end)

    {:reply, {:ok, resultados}, nuevo}
  end

  def handle_call(:reiniciar, _de, _estado) do
    Persistencia.eliminar(@archivo)
    {:reply, :ok, %{necesidades: %{}, siguiente: 1}}
  end

  # ---------------------------------------------------------------------------
  # Auxiliares
  # ---------------------------------------------------------------------------

  defp asignar_interno(estado, id, tipo, cantidad, usuario, opciones) do
    with {:ok, necesidad} <- buscar(estado, id),
         {:ok, cantidad} <- Emergencias.Validacion.entero_positivo(cantidad, :cantidad),
         :ok <- Necesidad.puede_asignar(necesidad, cantidad),
         opciones = Keyword.put_new(opciones, :preferir, [necesidad.zona]),
         {:ok, plan} <- retirar(necesidad, tipo, cantidad, usuario, opciones) do
      actualizada = Necesidad.registrar_asignacion(necesidad, plan)
      {:ok, actualizada, plan, poner(estado, actualizada)}
    end
  end

  defp retirar(necesidad, tipo, cantidad, usuario, opciones) do
    opciones = Keyword.merge(opciones, referencia: necesidad.id, usuario: usuario)
    Inventario.retirar(to_string(tipo), cantidad, opciones)
  end

  defp buscar(estado, id) do
    case Map.fetch(estado.necesidades, id) do
      {:ok, necesidad} -> {:ok, necesidad}
      :error -> {:error, {:no_encontrado, id}}
    end
  end

  defp poner(estado, necesidad) do
    necesidades = Map.put(estado.necesidades, necesidad.id, necesidad)
    Persistencia.guardar(@archivo, necesidades |> Map.values() |> Enum.map(&Necesidad.a_fila/1))
    %{estado | necesidades: necesidades}
  end

  defp siguiente_numero(necesidades) do
    necesidades
    |> Map.keys()
    |> Enum.map(fn "N" <> numero -> String.to_integer(numero) end)
    |> Enum.max(fn -> 0 end)
    |> Kernel.+(1)
  end
end
