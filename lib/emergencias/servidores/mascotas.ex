defmodule Emergencias.Servidores.Mascotas do
  @moduledoc """
  GenServer de reportes de mascotas perdidas y encontradas.

  El cálculo de coincidencias (costoso) se hace FUERA de este proceso, en paralelo,
  sobre una copia de los reportes; aquí solo se aplican los cambios de estado,
  que sí deben ser atómicos: un reporte resuelto no puede volver a resolverse.
  """

  use GenServer

  alias Emergencias.Persistencia
  alias Emergencias.Dominio.Mascota

  @archivo "mascotas.txt"

  # ---------------------------------------------------------------------------
  # API
  # ---------------------------------------------------------------------------

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  def reportar(attrs), do: GenServer.call(__MODULE__, {:reportar, attrs})
  def obtener(id), do: GenServer.call(__MODULE__, {:obtener, normalizar_id(id)})
  def listar(filtros \\ %{}), do: GenServer.call(__MODULE__, {:listar, filtros})

  @doc "Marca como `posible_coincidencia` los reportes activos indicados."
  def marcar_posibles(ids), do: GenServer.call(__MODULE__, {:marcar_posibles, ids})

  @doc "Confirma la coincidencia entre un reporte perdido y uno encontrado y cierra ambos."
  def confirmar(id_a, id_b),
    do: GenServer.call(__MODULE__, {:confirmar, normalizar_id(id_a), normalizar_id(id_b)})

  def reiniciar, do: GenServer.call(__MODULE__, :reiniciar)

  def normalizar_id(id) when is_binary(id), do: id |> String.trim() |> String.upcase()
  def normalizar_id(id), do: id

  # ---------------------------------------------------------------------------
  # Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(:ok) do
    mascotas =
      @archivo
      |> Persistencia.leer()
      |> Map.new(fn fila ->
        mascota = Mascota.desde_fila(fila)
        {mascota.id, mascota}
      end)

    siguiente =
      mascotas
      |> Map.keys()
      |> Enum.map(fn "PET" <> numero -> String.to_integer(numero) end)
      |> Enum.max(fn -> 0 end)
      |> Kernel.+(1)

    {:ok, %{mascotas: mascotas, siguiente: siguiente}}
  end

  @impl true
  def handle_call({:reportar, attrs}, _de, estado) do
    id = "PET" <> String.pad_leading(Integer.to_string(estado.siguiente), 3, "0")

    case Mascota.nueva(id, attrs) do
      {:ok, mascota} ->
        {:reply, {:ok, mascota}, %{estado | siguiente: estado.siguiente + 1} |> poner([mascota])}

      error ->
        {:reply, error, estado}
    end
  end

  def handle_call({:obtener, id}, _de, estado), do: {:reply, buscar(estado, id), estado}

  def handle_call({:listar, filtros}, _de, estado) do
    lista =
      estado.mascotas
      |> Map.values()
      |> Enum.filter(fn m ->
        Enum.all?(filtros, fn {campo, valor} -> Map.get(m, campo) == valor end)
      end)
      |> Enum.sort_by(& &1.id)

    {:reply, lista, estado}
  end

  def handle_call({:marcar_posibles, ids}, _de, estado) do
    actualizadas =
      ids
      |> Enum.uniq()
      |> Enum.flat_map(fn id ->
        with {:ok, %Mascota{estado: :activa} = mascota} <- buscar(estado, id),
             {:ok, actualizada} <- Mascota.cambiar_estado(mascota, :posible_coincidencia) do
          [actualizada]
        else
          _ -> []
        end
      end)

    {:reply, {:ok, actualizadas}, poner(estado, actualizadas)}
  end

  def handle_call({:confirmar, id_a, id_b}, _de, estado) do
    with {:ok, a} <- buscar(estado, id_a),
         {:ok, b} <- buscar(estado, id_b),
         :ok <- validar_par(a, b),
         {:ok, a_resuelta} <- Mascota.cambiar_estado(a, :resuelta),
         {:ok, b_resuelta} <- Mascota.cambiar_estado(b, :resuelta) do
      cerradas = [%{a_resuelta | coincidencia_con: b.id}, %{b_resuelta | coincidencia_con: a.id}]
      {:reply, {:ok, cerradas}, poner(estado, cerradas)}
    else
      error -> {:reply, error, estado}
    end
  end

  def handle_call(:reiniciar, _de, _estado) do
    Persistencia.eliminar(@archivo)
    {:reply, :ok, %{mascotas: %{}, siguiente: 1}}
  end

  # ---------------------------------------------------------------------------
  # Auxiliares
  # ---------------------------------------------------------------------------

  defp validar_par(%Mascota{tipo_reporte: igual}, %Mascota{tipo_reporte: igual}),
    do: {:error, :mismo_tipo_de_reporte}

  defp validar_par(%Mascota{especie: e1}, %Mascota{especie: e2}) when e1 != e2,
    do: {:error, :especies_distintas}

  defp validar_par(_a, _b), do: :ok

  defp buscar(estado, id) do
    case Map.fetch(estado.mascotas, id) do
      {:ok, mascota} -> {:ok, mascota}
      :error -> {:error, {:no_encontrado, id}}
    end
  end

  defp poner(estado, []), do: estado

  defp poner(estado, mascotas) do
    nuevas = Enum.reduce(mascotas, estado.mascotas, &Map.put(&2, &1.id, &1))
    Persistencia.guardar(@archivo, nuevas |> Map.values() |> Enum.map(&Mascota.a_fila/1))
    %{estado | mascotas: nuevas}
  end
end
