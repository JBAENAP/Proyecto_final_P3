defmodule Emergencias.Bitacora do
  @moduledoc """
  Registro de la actividad de cada usuario.

  Se implementa a propósito como un PROCESO INDEPENDIENTE "a mano" (sin GenServer):
  `spawn_link` + un ciclo `receive` recursivo que guarda su estado en el argumento.
  Así se evidencia el paso de mensajes básico de Elixir. Registrar actividad es
  asíncrono (`send/2`, no bloquea al usuario) y las consultas usan una referencia
  única (`make_ref/0`) para emparejar pregunta y respuesta.

  Se supervisa igual que cualquier otro hijo gracias a `child_spec/1`.
  """

  alias Emergencias.Persistencia

  @archivo "actividad.txt"
  @tiempo_espera 5_000

  def child_spec(_opts) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, []}, type: :worker, restart: :permanent}
  end

  def start_link do
    pid = spawn_link(fn -> iniciar() end)
    Process.register(pid, __MODULE__)
    {:ok, pid}
  end

  # ---------------------------------------------------------------------------
  # API
  # ---------------------------------------------------------------------------

  @doc "Registra una acción (asíncrono)."
  def registrar(usuario, accion, detalle, resultado) do
    entrada = {Persistencia.ahora(), usuario, accion, detalle, resultado}

    case Process.whereis(__MODULE__) do
      nil -> :ok
      pid -> send(pid, {:registrar, entrada})
    end

    :ok
  end

  @doc "Actividad registrada, opcionalmente filtrada por usuario (más reciente primero)."
  def consultar(usuario \\ nil, limite \\ 50), do: preguntar({:consultar, usuario, limite}, [])

  def reiniciar, do: preguntar(:reiniciar, :ok)

  defp preguntar(mensaje, por_defecto) do
    case Process.whereis(__MODULE__) do
      nil ->
        por_defecto

      pid ->
        referencia = make_ref()
        send(pid, {mensaje, self(), referencia})

        receive do
          {^referencia, respuesta} -> respuesta
        after
          @tiempo_espera -> por_defecto
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Proceso
  # ---------------------------------------------------------------------------

  defp iniciar do
    entradas = @archivo |> Persistencia.leer() |> Enum.map(&desde_fila/1) |> Enum.reverse()
    ciclo(entradas)
  end

  # Ciclo recursivo: cada mensaje procesado vuelve a llamar a ciclo/1 con el nuevo estado.
  defp ciclo(entradas) do
    receive do
      {:registrar, entrada} ->
        Persistencia.agregar(@archivo, a_fila(entrada))
        mostrar(entrada)
        ciclo([entrada | entradas])

      {{:consultar, usuario, limite}, de, referencia} ->
        resultado =
          entradas
          |> Enum.filter(fn {_fecha, u, _accion, _detalle, _res} ->
            usuario == nil or u == usuario
          end)
          |> Enum.take(limite)

        send(de, {referencia, resultado})
        ciclo(entradas)

      {:reiniciar, de, referencia} ->
        Persistencia.eliminar(@archivo)
        send(de, {referencia, :ok})
        ciclo([])

      _desconocido ->
        ciclo(entradas)
    end
  end

  # En la terminal del servidor (`mix servidor`) se muestra cada acción en vivo.
  defp mostrar({fecha, usuario, accion, detalle, resultado}) do
    if Application.get_env(:emergencias, :mostrar_actividad, false) do
      hora = Calendar.strftime(fecha, "%H:%M:%S")
      IO.puts("[#{hora}] #{usuario} -> #{accion} #{detalle} (#{resultado})")
    end
  end

  defp a_fila({fecha, usuario, accion, detalle, resultado}),
    do: [fecha, usuario, accion, detalle, resultado]

  defp desde_fila([fecha, usuario, accion, detalle, resultado]),
    do: {Persistencia.a_fecha(fecha), usuario, accion, detalle, resultado}
end
