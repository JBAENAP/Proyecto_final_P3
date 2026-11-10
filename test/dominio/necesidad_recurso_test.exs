defmodule Emergencias.Dominio.NecesidadRecursoTest do
  use ExUnit.Case, async: true

  alias Emergencias.Dominio.{Necesidad, Recurso}

  defp necesidad(id, prioridad, cantidad \\ 10) do
    {:ok, n} =
      Necesidad.nueva(id, %{
        tipo: "agua",
        cantidad: cantidad,
        prioridad: prioridad,
        zona: "centro",
        descripcion: "x"
      })

    n
  end

  describe "Necesidad" do
    test "valida los campos de entrada" do
      assert {:error, {:opcion_invalida, :tipo_necesidad, _}} =
               Necesidad.nueva("N1", %{
                 tipo: "gasolina",
                 cantidad: 1,
                 prioridad: "alta",
                 zona: "c"
               })

      assert {:error, {:debe_ser_positivo, :cantidad}} =
               Necesidad.nueva("N1", %{tipo: "agua", cantidad: 0, prioridad: "alta", zona: "c"})

      assert {:error, {:formato_invalido, :asociado_a, _}} =
               Necesidad.nueva("N1", %{
                 tipo: "agua",
                 cantidad: 1,
                 prioridad: "alta",
                 zona: "c",
                 asociado_a: "A01"
               })
    end

    test "asociación a albergue, persona o familia" do
      {:ok, n} =
        Necesidad.nueva("N1", %{
          tipo: "agua",
          cantidad: 1,
          prioridad: "alta",
          zona: "c",
          asociado_a: "albergue:A01"
        })

      assert {n.asociado_tipo, n.asociado_ref} == {:albergue, "A01"}
    end

    test "ordenar usa la prioridad" do
      lista = [
        necesidad("N1", "baja"),
        necesidad("N2", "critica"),
        necesidad("N3", "media"),
        necesidad("N4", "alta")
      ]

      assert lista |> Necesidad.ordenar() |> Enum.map(& &1.prioridad) == [
               :critica,
               :alta,
               :media,
               :baja
             ]
    end

    test "una necesidad cerrada no vuelve a consumir recursos" do
      n = necesidad("N1", "alta")
      {:ok, n} = Necesidad.cambiar_estado(n, :en_atencion)
      {:ok, n} = Necesidad.cambiar_estado(n, :atendida)
      assert Necesidad.puede_asignar(n, 1) == {:error, {:ya_cerrado, :atendida}}
      assert Necesidad.cambiar_estado(n, :atendida) == {:error, {:ya_cerrado, :atendida}}
    end

    test "no se asigna más de lo requerido" do
      n = necesidad("N1", "alta", 10) |> Necesidad.registrar_asignacion([{"R1", 8}])
      assert n.estado == :asignada
      assert Necesidad.faltante(n) == 2
      assert Necesidad.puede_asignar(n, 3) == {:error, {:excede_lo_requerido, 2}}
    end

    test "despachar recorre en orden y acumula resultados" do
      lista = [necesidad("N1", "critica"), necesidad("N2", "baja")]
      stock = :counters.new(1, [])
      :counters.put(stock, 1, 15)

      asignar = fn n ->
        disponible = :counters.get(stock, 1)
        tomado = min(disponible, Necesidad.faltante(n))

        if tomado > 0 do
          :counters.sub(stock, 1, tomado)
          {:ok, Necesidad.registrar_asignacion(n, [{"R1", tomado}]), [{"R1", tomado}]}
        else
          {:error, {:inventario_insuficiente, 0}}
        end
      end

      assert [{:asignada, n1, [{"R1", 10}]}, {:asignada, n2, [{"R1", 5}]}] =
               Necesidad.despachar(lista, asignar, [])

      assert {n1.asignada, n2.asignada} == {10, 5}
    end
  end

  describe "Recurso" do
    defp recurso(codigo, cantidad) do
      {:ok, r} =
        Recurso.nuevo(%{
          codigo: codigo,
          nombre: "Agua",
          cantidad: cantidad,
          unidad: "litros",
          ubicacion: "c1"
        })

      r
    end

    test "no se permiten cantidades negativas" do
      assert {:error, {:negativo, :cantidad}} =
               Recurso.nuevo(%{
                 codigo: "R",
                 nombre: "agua",
                 cantidad: -1,
                 unidad: "l",
                 ubicacion: "c"
               })

      assert Recurso.ajustar(recurso("R1", 5), -6) == {:error, {:inventario_insuficiente, 5}}
      assert {:ok, %Recurso{cantidad: 0}} = Recurso.ajustar(recurso("R1", 5), -5)
    end

    test "planificar_retiro reparte entre varios recursos (todo o nada)" do
      candidatos = [recurso("R1", 20), recurso("R2", 0), recurso("R3", 15)]
      assert Recurso.planificar_retiro(candidatos, 30) == {:ok, [{"R1", 20}, {"R3", 10}]}
      assert Recurso.planificar_retiro(candidatos, 35) == {:ok, [{"R1", 20}, {"R3", 15}]}
      assert Recurso.planificar_retiro(candidatos, 36) == :insuficiente
    end

    test "de_tipo? compara nombre o categoría normalizados" do
      {:ok, arroz} =
        Recurso.nuevo(%{
          codigo: "R",
          nombre: "Arroz",
          categoria: "Alimentos",
          cantidad: 1,
          unidad: "kg",
          ubicacion: "c"
        })

      assert Recurso.de_tipo?(arroz, "arroz")
      assert Recurso.de_tipo?(arroz, "alimentos")
      refute Recurso.de_tipo?(arroz, "agua")
    end
  end
end
