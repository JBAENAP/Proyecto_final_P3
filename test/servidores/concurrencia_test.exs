defmodule Emergencias.ConcurrenciaTest do
  @moduledoc """
  Conflictos concurrentes: muchas tareas atacan el mismo recurso al mismo tiempo.
  Cada prueba usa una "barrera" para que todas las tareas disparen juntas.
  """

  use Emergencias.CasoSistema, async: false

  alias Emergencias.Servidores.{Albergues, Inventario, Necesidades}

  # Lanza una tarea por elemento; todas esperan la señal :ya y luego ejecutan `fun`.
  defp en_paralelo(elementos, fun) do
    padre = self()

    tareas =
      Enum.map(elementos, fn elemento ->
        Task.async(fn ->
          send(padre, {:lista, self()})
          receive do: (:ya -> :ok)
          fun.(elemento)
        end)
      end)

    pids = Enum.map(tareas, fn _ -> receive(do: ({:lista, pid} -> pid)) end)
    Enum.each(pids, &send(&1, :ya))
    Enum.map(tareas, &Task.await(&1, 15_000))
  end

  setup do: con_demo()

  test "flujo del enunciado: 30 + 25 litros sobre 50 nunca asigna 55" do
    recurso!("R001", "agua", 50)
    n1 = necesidad!("agua", 30, "critica")
    n2 = necesidad!("agua", 25, "alta")

    resultados =
      en_paralelo([{n1.id, 30, "laura"}, {n2.id, 25, "otro"}], fn {id, cantidad, usuario} ->
        Emergencias.asignar_recurso(actor(:coordinador, usuario), id, "agua", cantidad)
      end)

    confirmados = Enum.count(resultados, &match?({:ok, _}, &1))
    rechazados = Enum.filter(resultados, &match?({:error, {:inventario_insuficiente, _}}, &1))

    assert confirmados == 1
    assert length(rechazados) == 1
    {:ok, recurso} = Inventario.obtener("R001")
    assert recurso.cantidad in [20, 25]
  end

  test "100 retiros simultáneos sobre 50 unidades: exactamente 50 confirmados" do
    recurso!("R1", "agua", 50)

    resultados = en_paralelo(1..100, fn i -> Inventario.retirar("agua", 1, usuario: "u#{i}") end)

    assert Enum.count(resultados, &match?({:ok, _}, &1)) == 50
    assert Enum.count(resultados, &match?({:error, {:inventario_insuficiente, 0}}, &1)) == 50
    assert {:ok, %{cantidad: 0}} = Inventario.obtener("R1")
    assert Inventario.historial("R1") |> Enum.count(&(&1.tipo == :asignacion)) == 50
  end

  test "pedidos de tamaño aleatorio: lo asignado nunca supera el stock y nunca hay negativos" do
    recurso!("R1", "agua", 100)
    recurso!("R2", "agua", 37)
    pedidos = Enum.map(1..60, fn _ -> Enum.random(1..12) end)

    resultados =
      en_paralelo(pedidos, fn cantidad -> {cantidad, Inventario.retirar("agua", cantidad)} end)

    asignado =
      resultados
      |> Enum.filter(&match?({_, {:ok, _}}, &1))
      |> Enum.map(&elem(&1, 0))
      |> Enum.sum()

    restante = Inventario.listar() |> Enum.map(& &1.cantidad) |> Enum.sum()

    assert asignado <= 137
    assert asignado + restante == 137
    assert Enum.all?(Inventario.listar(), &(&1.cantidad >= 0))
  end

  test "la misma necesidad pedida por muchos usuarios no se sobre-asigna" do
    recurso!("R1", "agua", 1_000)
    n = necesidad!("agua", 10, "critica")

    resultados = en_paralelo(1..20, fn i -> Necesidades.asignar(n.id, "agua", 3, "u#{i}") end)

    assert Enum.count(resultados, &match?({:ok, _, _}, &1)) == 3
    {:ok, final} = Necesidades.obtener(n.id)
    assert final.asignada == 9
    assert {:ok, %{cantidad: 991}} = Inventario.obtener("R1")
  end

  test "cerrar la misma necesidad en paralelo solo funciona una vez" do
    n = necesidad!("rescate", 1, "critica")
    {:ok, _} = Necesidades.cambiar_estado(n.id, :en_atencion)

    resultados = en_paralelo(1..10, fn _ -> Necesidades.cambiar_estado(n.id, :atendida) end)

    assert Enum.count(resultados, &match?({:ok, _}, &1)) == 1
    assert Enum.count(resultados, &(&1 == {:error, {:ya_cerrado, :atendida}})) == 9
  end

  test "ingresos simultáneos nunca superan la capacidad del albergue" do
    {:ok, _} =
      Albergues.registrar(%{codigo: "A9", nombre: "Chico", zona: "centro", capacidad: 10})

    resultados = en_paralelo(1..40, fn i -> Albergues.ingresar("A9", "doc#{i}") end)

    assert Enum.count(resultados, &match?({:ok, _}, &1)) == 10
    assert {:ok, %{ocupacion: 10}} = Albergues.obtener("A9")
  end

  test "la simulación de la consola confirma solo lo que cabe" do
    {:ok, s} = Emergencias.simular_conflicto(actor(:coordinador), "centro_acopio_1", 50, [30, 25])
    assert s.total_asignado in [25, 30]
    assert s.stock_final == 50 - s.total_asignado
    assert Enum.count(s.resultados, &match?({_, _, _, {:error, _}}, &1)) == 1
  end
end
