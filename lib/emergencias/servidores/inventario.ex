defmodule Emergencias.Servidores.Inventario do
  @moduledoc """
  GenServer dueño del inventario de recursos y de su historial de movimientos.

  ## Regla de concurrencia

  Toda lectura-y-modificación del stock ocurre dentro de un `handle_call`. Un
  GenServer procesa los mensajes de su mailbox de uno en uno, así que "verificar
  disponibilidad" y "descontar" forman una sola operación atómica: si dos usuarios
  piden al mismo tiempo las últimas unidades, la segunda solicitud ya ve el stock
  descontado por la primera y es rechazada. La cantidad asignada nunca supera el
  inventario real y ningún recurso queda en negativo.
  """

  use GenServer

  alias Emergencias.{Persistencia, Validacion}
  alias Emergencias.Dominio.{Movimiento, Recurso}

  @archivo "recursos.txt"
  @archivo_movimientos "movimientos.txt"

  # ---------------------------------------------------------------------------
  # API
  # ---------------------------------------------------------------------------

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  def registrar(attrs, usuario), do: GenServer.call(__MODULE__, {:registrar, attrs, usuario})

  def entrada(codigo, cantidad, usuario, referencia \\ ""),
    do: GenServer.call(__MODULE__, {:ajustar, :entrada, codigo, cantidad, usuario, referencia})

  def salida(codigo, cantidad, usuario, referencia \\ ""),
    do: GenServer.call(__MODULE__, {:ajustar, :salida, codigo, cantidad, usuario, referencia})

  @doc """
  Retira `cantidad` unidades de recursos del `tipo` dado y devuelve el plan
  `[{codigo, cantidad}]`. Opciones:

    * `:preferir` – códigos de zona/ubicación cuyos recursos se usan primero
    * `:desde` – código de un recurso específico
    * `:parcial` – si es `true` entrega lo que haya (hasta `cantidad`) en vez de todo o nada
    * `:referencia`, `:usuario` – para el historial
  """
  def retirar(tipo, cantidad, opciones \\ []),
    do: GenServer.call(__MODULE__, {:retirar, tipo, cantidad, opciones})

  def transferir(codigo, origen, destino, zona_destino, cantidad, usuario),
    do:
      GenServer.call(
        __MODULE__,
        {:transferir, codigo, origen, destino, zona_destino, cantidad, usuario}
      )

  def obtener(codigo), do: GenServer.call(__MODULE__, {:obtener, codigo})
  def listar, do: GenServer.call(__MODULE__, :listar)
  def historial(codigo \\ nil), do: GenServer.call(__MODULE__, {:historial, codigo})
  def reiniciar, do: GenServer.call(__MODULE__, :reiniciar)

  # ---------------------------------------------------------------------------
  # Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(:ok) do
    recursos =
      @archivo
      |> Persistencia.leer()
      |> Map.new(fn fila ->
        recurso = Recurso.desde_fila(fila)
        {recurso.codigo, recurso}
      end)

    movimientos =
      @archivo_movimientos
      |> Persistencia.leer()
      |> Enum.map(&Movimiento.desde_fila/1)
      |> Enum.reverse()

    {:ok, %{recursos: recursos, movimientos: movimientos}}
  end

  @impl true
  def handle_call({:registrar, attrs, usuario}, _de, estado) do
    with {:ok, recurso} <- Recurso.nuevo(attrs),
         :ok <- no_duplicado(estado.recursos, recurso.codigo) do
      movimiento =
        Movimiento.nuevo(
          :registro,
          recurso.codigo,
          recurso.cantidad,
          recurso.cantidad,
          "alta",
          usuario
        )

      nuevo = estado |> poner_recurso(recurso) |> anotar([movimiento])
      {:reply, {:ok, recurso}, nuevo}
    else
      error -> {:reply, error, estado}
    end
  end

  def handle_call({:ajustar, tipo, codigo, cantidad, usuario, referencia}, _de, estado) do
    with {:ok, cantidad} <- Validacion.entero_positivo(cantidad, :cantidad),
         {:ok, recurso} <- buscar(estado, codigo),
         delta = if(tipo == :entrada, do: cantidad, else: -cantidad),
         {:ok, actualizado} <- Recurso.ajustar(recurso, delta) do
      movimiento =
        Movimiento.nuevo(tipo, codigo, cantidad, actualizado.cantidad, referencia, usuario)

      {:reply, {:ok, actualizado}, estado |> poner_recurso(actualizado) |> anotar([movimiento])}
    else
      error -> {:reply, error, estado}
    end
  end

  def handle_call({:retirar, tipo, cantidad, opciones}, _de, estado) do
    with {:ok, cantidad} <- Validacion.entero_positivo(cantidad, :cantidad),
         {:ok, candidatos} <- candidatos(estado, tipo, opciones),
         {:ok, plan} <- planificar(candidatos, cantidad, Keyword.get(opciones, :parcial, false)) do
      {nuevo, _} = aplicar_plan(estado, plan, opciones)
      {:reply, {:ok, plan}, nuevo}
    else
      error -> {:reply, error, estado}
    end
  end

  def handle_call(
        {:transferir, codigo, origen, destino, zona_destino, cantidad, usuario},
        _de,
        estado
      ) do
    with {:ok, cantidad} <- Validacion.entero_positivo(cantidad, :cantidad),
         {:ok, recurso} <- buscar(estado, codigo),
         :ok <- validar_origen(recurso, origen),
         :ok <- validar_destino(origen, destino),
         {:ok, origen_actualizado} <- Recurso.ajustar(recurso, -cantidad) do
      {destino_actualizado, creado?} =
        recurso_destino(estado, recurso, destino, zona_destino, cantidad)

      referencia = "#{origen}->#{destino}"

      movimientos = [
        Movimiento.nuevo(
          :transferencia_salida,
          codigo,
          cantidad,
          origen_actualizado.cantidad,
          referencia,
          usuario
        ),
        Movimiento.nuevo(
          :transferencia_entrada,
          destino_actualizado.codigo,
          cantidad,
          destino_actualizado.cantidad,
          referencia,
          usuario
        )
      ]

      nuevo =
        estado
        |> poner_recurso(origen_actualizado)
        |> poner_recurso(destino_actualizado)
        |> anotar(movimientos)

      {:reply,
       {:ok, %{origen: origen_actualizado, destino: destino_actualizado, nuevo_recurso: creado?}},
       nuevo}
    else
      error -> {:reply, error, estado}
    end
  end

  def handle_call({:obtener, codigo}, _de, estado), do: {:reply, buscar(estado, codigo), estado}

  def handle_call(:listar, _de, estado) do
    {:reply, estado.recursos |> Map.values() |> Enum.sort_by(& &1.codigo), estado}
  end

  def handle_call({:historial, nil}, _de, estado),
    do: {:reply, Enum.reverse(estado.movimientos), estado}

  def handle_call({:historial, codigo}, _de, estado) do
    movimientos = estado.movimientos |> Enum.filter(&(&1.codigo == codigo)) |> Enum.reverse()
    {:reply, movimientos, estado}
  end

  def handle_call(:reiniciar, _de, _estado) do
    Persistencia.eliminar(@archivo)
    Persistencia.eliminar(@archivo_movimientos)
    {:reply, :ok, %{recursos: %{}, movimientos: []}}
  end

  # ---------------------------------------------------------------------------
  # Auxiliares (se ejecutan dentro del proceso, por eso son atómicas)
  # ---------------------------------------------------------------------------

  defp buscar(estado, codigo) do
    case Map.fetch(estado.recursos, codigo) do
      {:ok, recurso} -> {:ok, recurso}
      :error -> {:error, {:no_encontrado, codigo}}
    end
  end

  defp no_duplicado(recursos, codigo) do
    if Map.has_key?(recursos, codigo), do: {:error, {:id_duplicado, codigo}}, else: :ok
  end

  # Recursos que pueden atender el pedido, los preferidos (misma zona) primero
  # y luego los de mayor existencia.
  defp candidatos(estado, tipo, opciones) do
    case Keyword.get(opciones, :desde) do
      nil ->
        preferir = Keyword.get(opciones, :preferir, [])

        lista =
          estado.recursos
          |> Map.values()
          |> Enum.filter(&Recurso.de_tipo?(&1, tipo))
          |> Enum.sort_by(fn r ->
            {not (r.zona in preferir or r.ubicacion in preferir), -r.cantidad, r.codigo}
          end)

        if lista == [], do: {:error, {:sin_recursos_de_tipo, tipo}}, else: {:ok, lista}

      codigo ->
        with {:ok, recurso} <- buscar(estado, codigo) do
          if Recurso.de_tipo?(recurso, tipo),
            do: {:ok, [recurso]},
            else: {:error, {:tipo_no_coincide, codigo, tipo}}
        end
    end
  end

  defp planificar(candidatos, cantidad, parcial?) do
    disponible = candidatos |> Enum.map(& &1.cantidad) |> Enum.sum()

    cond do
      disponible >= cantidad -> Recurso.planificar_retiro(candidatos, cantidad)
      parcial? and disponible > 0 -> Recurso.planificar_retiro(candidatos, disponible)
      true -> {:error, {:inventario_insuficiente, disponible}}
    end
  end

  defp aplicar_plan(estado, plan, opciones) do
    referencia = Keyword.get(opciones, :referencia, "")
    usuario = Keyword.get(opciones, :usuario)

    Enum.reduce(plan, {estado, []}, fn {codigo, cantidad}, {acc, movs} ->
      {:ok, actualizado} = Recurso.ajustar(Map.fetch!(acc.recursos, codigo), -cantidad)

      movimiento =
        Movimiento.nuevo(:asignacion, codigo, cantidad, actualizado.cantidad, referencia, usuario)

      {acc |> poner_recurso(actualizado) |> anotar([movimiento]), [movimiento | movs]}
    end)
  end

  defp validar_origen(%Recurso{ubicacion: origen}, origen), do: :ok

  defp validar_origen(%Recurso{ubicacion: real}, _origen),
    do: {:error, {:origen_incorrecto, real}}

  defp validar_destino(igual, igual), do: {:error, :origen_igual_destino}
  defp validar_destino(_origen, _destino), do: :ok

  # Si en el destino ya hay un recurso del mismo nombre y unidad se suma ahí;
  # si no, se crea uno nuevo con código `<codigo>-<destino>`.
  defp recurso_destino(estado, recurso, destino, zona_destino, cantidad) do
    existente =
      estado.recursos
      |> Map.values()
      |> Enum.find(
        &(&1.ubicacion == destino and &1.nombre == recurso.nombre and &1.unidad == recurso.unidad)
      )

    case existente do
      nil ->
        {%{
           recurso
           | codigo: codigo_libre(estado.recursos, "#{recurso.codigo}-#{destino}"),
             cantidad: cantidad,
             ubicacion: destino,
             zona: zona_destino,
             creado_en: Persistencia.ahora()
         }, true}

      encontrado ->
        {%{encontrado | cantidad: encontrado.cantidad + cantidad}, false}
    end
  end

  defp codigo_libre(recursos, base, n \\ 1) do
    candidato = if n == 1, do: base, else: "#{base}-#{n}"
    if Map.has_key?(recursos, candidato), do: codigo_libre(recursos, base, n + 1), else: candidato
  end

  defp poner_recurso(estado, recurso) do
    nuevos = Map.put(estado.recursos, recurso.codigo, recurso)
    Persistencia.guardar(@archivo, nuevos |> Map.values() |> Enum.map(&Recurso.a_fila/1))
    %{estado | recursos: nuevos}
  end

  defp anotar(estado, movimientos) do
    Enum.each(movimientos, &Persistencia.agregar(@archivo_movimientos, Movimiento.a_fila(&1)))
    %{estado | movimientos: Enum.reverse(movimientos) ++ estado.movimientos}
  end
end
