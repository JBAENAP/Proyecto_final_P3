defmodule Emergencias.Dominio.ZonaTest do
  use ExUnit.Case, async: true

  alias Emergencias.Dominio.Zona

  # centro (100) -> sector_1 (40) -> punto_a
  #              -> sector_2 (60)
  # norte  (10)
  defp arbol do
    {:ok, centro} = Zona.nuevo(:zona, "centro", "Centro", "critico", 100)
    {:ok, norte} = Zona.nuevo(:zona, "norte", "Norte", "bajo", 10)
    {:ok, s1} = Zona.nuevo(:sector, "sector_1", "Sector 1", "alto", 40)
    {:ok, s2} = Zona.nuevo(:sector, "sector_2", "Sector 2", "medio", 60)
    {:ok, punto} = Zona.nuevo(:punto, "punto_a", "Punto A", nil, 0, "acopio")

    {:ok, arbol} = Zona.insertar([centro, norte], "centro", s1)
    {:ok, arbol} = Zona.insertar(arbol, "centro", s2)
    {:ok, arbol} = Zona.insertar(arbol, "sector_1", punto)
    arbol
  end

  test "buscar recorre todos los niveles" do
    assert %Zona{codigo: "punto_a", tipo: :punto} = Zona.buscar(arbol(), "punto_a")
    assert %Zona{codigo: "norte"} = Zona.buscar(arbol(), "norte")
    assert Zona.buscar(arbol(), "no_existe") == nil
  end

  test "ruta y raíz de un nodo" do
    assert Zona.ruta(arbol(), "punto_a") == ["centro", "sector_1", "punto_a"]
    assert Zona.raiz(arbol(), "sector_2") == "centro"
    assert Zona.ruta(arbol(), "x") == nil
  end

  test "la jerarquía zona → sector → punto se respeta" do
    {:ok, otro_punto} = Zona.nuevo(:punto, "p2", "P2", nil, 0, "atencion")

    assert Zona.insertar(arbol(), "centro", otro_punto) ==
             {:error, {:jerarquia_invalida, :zona, :punto}}

    assert Zona.insertar(arbol(), "no_existe", otro_punto) ==
             {:error, {:no_encontrado, "no_existe"}}
  end

  test "codigos devuelve todo el subárbol" do
    centro = Zona.buscar(arbol(), "centro")
    assert Enum.sort(Zona.codigos(centro)) == ["centro", "punto_a", "sector_1", "sector_2"]
  end

  test "acumular suma recursivamente las estadísticas de los descendientes" do
    centro = Zona.buscar(arbol(), "centro")
    necesidades = %{"centro" => 1, "sector_1" => 2, "punto_a" => 3, "sector_2" => 4}

    resultado =
      Zona.acumular(centro, fn codigo -> %{necesidades: Map.get(necesidades, codigo, 0)} end)

    assert resultado.totales == %{necesidades: 10, personas_afectadas: 200}
    [s1, s2] = resultado.hijos
    assert s1.totales == %{necesidades: 5, personas_afectadas: 40}
    assert s2.propias == %{necesidades: 4, personas_afectadas: 60}
  end

  test "actualizar modifica un nodo profundo" do
    {:ok, nuevo} = Zona.actualizar(arbol(), "sector_2", &%{&1 | nivel: :critico})
    assert Zona.buscar(nuevo, "sector_2").nivel == :critico
    assert Zona.actualizar(arbol(), "x", & &1) == :no_encontrado
  end

  test "aplanar y reconstruir desde filas conserva el árbol" do
    original = arbol()

    assert original |> Zona.aplanar() |> Enum.map(fn {p, n} -> {p, n.codigo} end) ==
             [{0, "centro"}, {1, "sector_1"}, {2, "punto_a"}, {1, "sector_2"}, {0, "norte"}]

    filas =
      original
      |> Zona.a_filas()
      |> Enum.map(fn f -> Enum.map(f, &Emergencias.Persistencia.a_texto/1) end)

    assert Zona.desde_filas(filas) == original
  end
end
