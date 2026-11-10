defmodule Emergencias.Simulacion do
  @moduledoc """
  Demostración del conflicto concurrente del enunciado.

  Se registra un recurso con `stock` unidades y una necesidad por cada pedido.
  Luego se lanza una tarea por pedido (cada una actúa como un usuario distinto).
  Todas esperan en una "barrera" hasta recibir `:ya` y entonces piden el recurso
  al mismo tiempo. El inventario serializa las solicitudes: solo se confirman las
  que caben en el stock real y la suma asignada nunca supera el stock inicial.

  Ejemplo del enunciado: 50 litros disponibles, pedidos de 30 y 25 → se confirma
  uno y el otro es rechazado por inventario insuficiente (nunca se asignan 55).
  """

  alias Emergencias.Servidores.Inventario

  def conflicto(actor, ubicacion, stock, pedidos) do
    codigo = "SIM" <> Integer.to_string(System.unique_integer([:positive]))

    with {:ok, recurso} <-
           Emergencias.registrar_recurso(actor, %{
             codigo: codigo,
             nombre: "agua",
             cantidad: stock,
             unidad: "litros",
             ubicacion: ubicacion,
             categoria: "agua"
           }),
         {:ok, necesidades} <- crear_necesidades(actor, ubicacion, pedidos) do
      padre = self()

      tareas =
        necesidades
        |> Enum.with_index(1)
        |> Enum.map(fn {necesidad, i} ->
          usuario_simulado = %{actor | username: "simulado_#{i}"}

          Task.Supervisor.async(Emergencias.Tareas, fn ->
            send(padre, {:lista, self()})

            receive do
              :ya -> :ok
            end

            opciones = [desde: codigo]

            resultado =
              Emergencias.asignar_recurso(
                usuario_simulado,
                necesidad.id,
                "agua",
                necesidad.cantidad,
                opciones
              )

            {usuario_simulado.username, necesidad.id, necesidad.cantidad, resultado}
          end)
        end)

      # Barrera: esperar a que todas las tareas estén listas y soltarlas a la vez.
      pids = Enum.map(tareas, fn _ -> receive(do: ({:lista, pid} -> pid)) end)
      Enum.each(pids, &send(&1, :ya))

      resultados = Enum.map(tareas, &Task.await(&1, 10_000))
      {:ok, final} = Inventario.obtener(codigo)

      total_asignado =
        resultados
        |> Enum.filter(&match?({_, _, _, {:ok, _}}, &1))
        |> Enum.map(fn {_, _, cantidad, _} -> cantidad end)
        |> Enum.sum()

      {:ok,
       %{
         recurso: recurso.codigo,
         stock_inicial: stock,
         pedidos: pedidos,
         resultados: resultados,
         total_asignado: total_asignado,
         stock_final: final.cantidad
       }}
    end
  end

  defp crear_necesidades(actor, ubicacion, pedidos) do
    Enum.reduce_while(Enum.with_index(pedidos, 1), {:ok, []}, fn {cantidad, i}, {:ok, acc} ->
      attrs = %{
        tipo: "agua",
        cantidad: cantidad,
        prioridad: "critica",
        zona: ubicacion,
        descripcion: "[SIMULACION] pedido del usuario simulado_#{i}"
      }

      case Emergencias.registrar_necesidad(actor, attrs) do
        {:ok, necesidad} -> {:cont, {:ok, acc ++ [necesidad]}}
        error -> {:halt, error}
      end
    end)
  end
end
