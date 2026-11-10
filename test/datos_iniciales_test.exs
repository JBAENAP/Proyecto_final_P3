defmodule Emergencias.DatosInicialesTest do
  use Emergencias.CasoSistema, async: false

  alias Emergencias.DatosIniciales
  alias Emergencias.Servidores.{Albergues, Familias, Inventario, Mascotas, Necesidades, Zonas}

  test "carga los datos de Armenia sin errores y solo una vez" do
    assert {:ok, %{usuarios: 4, errores: [], creados: creados}} = DatosIniciales.cargar_si_vacio()
    assert creados > 80

    # Las 10 comunas más el corregimiento El Caimo.
    zonas = Enum.map(Zonas.arbol(), & &1.codigo)
    assert length(zonas) == 11
    assert "comuna_10" in zonas and "el_caimo" in zonas

    assert length(Albergues.listar()) == 5
    assert length(Inventario.listar()) == 13
    assert length(Mascotas.listar()) == 5
    assert length(Familias.listar_mensajes()) == 4

    # Una segunda carga no duplica nada.
    assert {:ok, :ya_habia_datos} = DatosIniciales.cargar_si_vacio()
    assert length(Familias.buscar_personas(%{})) == 8
  end

  test "las necesidades quedan en distintos estados y el inventario descontado" do
    {:ok, _} = DatosIniciales.cargar()
    estados = Necesidades.listar() |> Enum.frequencies_by(& &1.estado)

    assert estados == %{pendiente: 6, asignada: 1, atendida: 1, cancelada: 1}
    agua = Inventario.listar() |> Enum.filter(&(&1.nombre == "agua")) |> Enum.map(& &1.cantidad)
    assert Enum.sum(agua) == 3900 - 200
    assert {:ok, %{cantidad: 95}} = Inventario.obtener("R008")
    assert {:ok, %{ocupacion: 143}} = Albergues.obtener("AL01")
    assert {:ok, %{estado: :en_albergue}} = Familias.obtener_persona("1094001001")
  end

  test "hay un usuario de cada tipo y todos entran con la clave 0000" do
    {:ok, _} = DatosIniciales.cargar()

    for {username, tipo} <- DatosIniciales.usuarios() do
      assert {:ok, %{usuario: usuario, modo: :autenticado}} =
               Emergencias.conectar(username, "0000")

      assert Atom.to_string(usuario.tipo) == tipo
    end
  end

  test "las mascotas de muestra producen coincidencias" do
    {:ok, _} = DatosIniciales.cargar()
    {:ok, %{usuario: andres}} = Emergencias.conectar("andres", "0000")
    assert {:ok, [_ | _] = coincidencias} = Emergencias.buscar_coincidencias(andres)
    assert Enum.all?(coincidencias, &(&1.puntaje >= 60))
  end
end
