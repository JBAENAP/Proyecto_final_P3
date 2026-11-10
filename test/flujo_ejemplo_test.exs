defmodule Emergencias.FlujoEjemploTest do
  @moduledoc "Reproduce el flujo de ejemplo de la sección 1.4.10 del enunciado."

  use Emergencias.CasoSistema, async: false

  test "flujo completo del enunciado" do
    # Laura se conecta como coordinadora de la zona centro
    {:ok, %{usuario: laura, sesion: sesion_laura}} =
      Emergencias.conectar("laura", "1234", "coordinador", "centro")

    {:ok, _} = Emergencias.cargar_demo(laura)

    # Registra una necesidad crítica de 30 litros de agua para un punto de atención
    {:ok, n1} =
      Emergencias.registrar_necesidad(laura, %{
        tipo: "agua",
        cantidad: "30",
        prioridad: "critica",
        zona: "centro",
        descripcion: "Punto de atención sector 3"
      })

    # El centro de acopio registra 50 litros disponibles
    {:ok, _} =
      Emergencias.registrar_recurso(laura, %{
        codigo: "R001",
        nombre: "agua",
        cantidad: "50",
        unidad: "litros",
        ubicacion: "centro_acopio_1"
      })

    # Al mismo tiempo, otro usuario registra una necesidad de 25 litros sobre el mismo recurso
    {:ok, %{usuario: otro}} = Emergencias.conectar("carlos", "abcd", "coordinador", "centro")

    {:ok, n2} =
      Emergencias.registrar_necesidad(otro, %{
        tipo: "agua",
        cantidad: "25",
        prioridad: "alta",
        zona: "sector_3"
      })

    # El sistema procesa ambas solicitudes sin permitir que se asignen 55 litros
    [r1, r2] =
      [{laura, n1.id, 30}, {otro, n2.id, 25}]
      |> Enum.map(fn {actor, id, cantidad} ->
        Task.async(fn ->
          Emergencias.asignar_recurso(actor, id, "agua", cantidad, desde: "R001")
        end)
      end)
      |> Enum.map(&Task.await/1)

    assert Enum.count([r1, r2], &match?({:ok, _}, &1)) == 1
    {:ok, inventario} = Emergencias.disponibilidad(laura, "agua")
    assert inventario.total in [20, 25]

    # Un ciudadano registra a Andrés como persona localizada en el Albergue Norte
    {:ok, %{usuario: ciudadano}} =
      Emergencias.conectar("pedro", "clave1", "ciudadano", "zona_norte")

    {:ok, _} =
      Emergencias.reportar_persona(ciudadano, %{
        documento: "1001",
        nombre: "Andrés",
        zona: "A01",
        estado: "localizada"
      })

    {:ok, %{usuario: voluntario}} =
      Emergencias.conectar("juan", "clave3", "voluntario", "zona_norte")

    {:ok, %{nota: :persona_actualizada}} =
      Emergencias.registrar_ingreso(voluntario, "A01", "1001")

    # Un familiar deja un mensaje para Andrés
    {:ok, %{usuario: familiar}} = Emergencias.conectar("maria", "clave2")

    {:ok, _} =
      Emergencias.enviar_mensaje(familiar, "1001", "Estoy bien, estoy en el albergue norte")

    # Un voluntario registra una mascota encontrada donde existe un reporte de mascota perdida
    {:ok, perdida} =
      Emergencias.reportar_mascota(familiar, %{
        tipo_reporte: "lost",
        especie: "perro",
        nombre: "Luna",
        color: "negra",
        tamano: "mediana",
        zona: "zona_norte",
        contacto: "300111"
      })

    {:ok, encontrada} =
      Emergencias.reportar_mascota(voluntario, %{
        tipo_reporte: "found",
        especie: "perro",
        nombre: "desconocido",
        color: "negra",
        tamano: "mediana",
        zona: "zona_norte",
        contacto: "300222"
      })

    # El sistema calcula posibles coincidencias
    {:ok, [coincidencia]} = Emergencias.buscar_coincidencias(voluntario)
    assert {coincidencia.perdida, coincidencia.encontrada} == {perdida.id, encontrada.id}
    assert coincidencia.puntaje >= 60

    # Un coordinador consulta el resumen global
    {:ok, resumen} = Emergencias.resumen(laura)
    assert [{"agua", restante, "litros"}] = resumen.recursos_por_tipo
    assert restante in [20, 25]
    assert map_size(resumen.pendientes_por_prioridad) > 0
    assert resumen.personas_localizadas == 1
    assert resumen.mensajes_total == 1
    assert resumen.mascotas_por_estado == %{posible_coincidencia: 2}
    assert resumen.ocupacion_total == 1
    assert resumen.usuarios_conectados == 5

    {:ok, _} = Emergencias.desconectar(sesion_laura)
  end
end
