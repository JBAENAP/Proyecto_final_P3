defmodule Emergencias.Dominio.MascotaAlbergueTest do
  use ExUnit.Case, async: true

  alias Emergencias.Dominio.{Albergue, Coincidencias, Mascota}

  defp mascota(id, tipo, attrs) do
    base = %{
      tipo_reporte: tipo,
      especie: "perro",
      nombre: "desconocido",
      color: "negra",
      tamano: "mediana",
      zona: "zona_norte",
      contacto: "300",
      caracteristicas: ""
    }

    {:ok, m} = Mascota.nueva(id, Map.merge(base, attrs))
    m
  end

  describe "Coincidencias" do
    test "el ejemplo del enunciado tiene puntaje alto" do
      perdida = mascota("PET001", "lost", %{nombre: "Luna", caracteristicas: "collar rojo"})

      encontrada =
        mascota("PET002", "found", %{
          color: "negro",
          tamano: "mediano",
          caracteristicas: "collar rojo"
        })

      {puntaje, detalle} = Coincidencias.puntaje(perdida, encontrada)

      assert detalle == %{
               especie: 30,
               color: 20,
               tamano: 15,
               zona: 15,
               nombre: 5,
               caracteristicas: 10
             }

      assert puntaje == 95
    end

    test "especies distintas nunca coinciden" do
      perro = mascota("A", "lost", %{})
      gato = mascota("B", "found", %{especie: "gato"})
      assert Coincidencias.puntaje(perro, gato) == {0, %{especie: 0}}
    end

    test "la misma zona raíz suma puntaje parcial y nombres distintos restan" do
      a = mascota("A", "lost", %{zona: "sector_1", nombre: "Luna"})
      b = mascota("B", "found", %{zona: "sector_2", nombre: "Rocky", tamano: "grande"})

      {_, detalle} =
        Coincidencias.puntaje(a, b, %{"sector_1" => "centro", "sector_2" => "centro"})

      assert detalle.zona == 8
      assert detalle.nombre == 0
      assert detalle.tamano == 7
    end

    test "buscar filtra por umbral y ordena por puntaje" do
      perdida = mascota("P1", "lost", %{})
      casi = mascota("E1", "found", %{color: "blanco", tamano: "grande"})
      igual = mascota("E2", "found", %{})
      resultado = Coincidencias.buscar([perdida], [casi, igual], 60)
      assert Enum.map(resultado, & &1.encontrada) == ["E2"]
    end

    test "jaccard sobre MapSet" do
      assert Coincidencias.jaccard(MapSet.new([1, 2]), MapSet.new([2, 3])) == 1 / 3
      assert Coincidencias.jaccard(MapSet.new(), MapSet.new()) == 0.0
    end
  end

  describe "Albergue" do
    defp albergue(codigo, capacidad, ocupacion \\ 0) do
      {:ok, a} =
        Albergue.nuevo(%{
          codigo: codigo,
          nombre: "A",
          zona: "z",
          capacidad: capacidad,
          ocupacion: ocupacion
        })

      a
    end

    test "no se supera la capacidad ni se admiten duplicados" do
      a = albergue("A1", 2)
      {:ok, a} = Albergue.ingresar(a, "d1")
      assert Albergue.ingresar(a, "d1") == {:error, {:ya_esta_en_albergue, "d1"}}
      {:ok, a} = Albergue.ingresar(a, "d2")
      assert Albergue.ingresar(a, "d3") == {:error, {:capacidad_superada, 2}}
      assert Albergue.cupos(a) == 0
    end

    test "salida solo de quien está registrado" do
      {:ok, a} = Albergue.ingresar(albergue("A1", 5), "d1")
      assert {:ok, %Albergue{ocupacion: 0}} = Albergue.salir(a, "d1")
      assert Albergue.salir(a, "d9") == {:error, {:no_esta_en_albergue, "d9"}}
    end

    test "capacidad y ocupación iniciales válidas" do
      assert {:error, {:capacidad_superada, 10}} =
               Albergue.nuevo(%{
                 codigo: "A",
                 nombre: "A",
                 zona: "z",
                 capacidad: 10,
                 ocupacion: 11
               })

      assert {:error, {:debe_ser_positivo, :capacidad}} =
               Albergue.nuevo(%{codigo: "A", nombre: "A", zona: "z", capacidad: 0})
    end

    test "top devuelve los de mayor porcentaje de ocupación" do
      lista = [
        albergue("A", 100, 10),
        albergue("B", 10, 9),
        albergue("C", 50, 40),
        albergue("D", 20, 2)
      ]

      assert lista |> Albergue.top(2) |> Enum.map(& &1.codigo) == ["B", "C"]
      assert lista |> Albergue.top(10) |> Enum.map(& &1.codigo) == ["B", "C", "A", "D"]
    end
  end
end
