defmodule Emergencias.ServidoresTest do
  use Emergencias.CasoSistema, async: false

  alias Emergencias.Servidores.{Inventario, Usuarios}

  describe "usuarios y conexión" do
    test "registro automático y validación de contraseña" do
      assert {:ok, u, :registrado} = Usuarios.conectar("Laura", "1234", "coordinadora", "centro")
      assert {u.username, u.tipo, u.zona} == {"laura", :coordinador, "centro"}
      refute u.hash == "1234"

      assert {:ok, _, :autenticado} = Usuarios.conectar("laura", "1234")
      assert Usuarios.conectar("laura", "mala") == {:error, :clave_incorrecta}
    end

    test "valida datos de registro" do
      assert Usuarios.conectar("ab", "1234") == {:error, :usuario_invalido}
      assert Usuarios.conectar("pepe", "12") == {:error, :clave_muy_corta}

      assert {:error, {:opcion_invalida, :tipo_usuario, _}} =
               Usuarios.conectar("pepe", "1234", "rey")
    end

    test "los permisos dependen del rol" do
      ciudadano = actor(:ciudadano)

      assert Emergencias.registrar_zona(ciudadano, "z1", "Z", "alto") ==
               {:error, {:sin_permiso, :register_zone, :ciudadano}}

      assert {:ok, _} = Emergencias.registrar_zona(actor(:coordinador), "z1", "Z", "alto")

      assert {:error, {:sin_permiso, :list_users, :coordinador}} =
               Emergencias.listar_usuarios(actor(:coordinador))
    end

    test "la actividad de cada usuario queda en la bitácora" do
      coordinador = actor(:coordinador, "laura")
      {:ok, _} = Emergencias.registrar_zona(coordinador, "z1", "Z", "alto")
      {:error, _} = Emergencias.registrar_zona(coordinador, "z1", "Z", "alto")

      {:ok, actividad} = Emergencias.actividad(coordinador)

      assert [
               {_, "laura", "register_zone", "z1", "error"},
               {_, "laura", "register_zone", "z1", "ok"}
             ] = actividad

      assert {:error, {:sin_permiso, :activity_all, :coordinador}} =
               Emergencias.actividad(coordinador, "otro")
    end
  end

  describe "zonas" do
    setup do: con_demo()

    test "identificadores únicos en todo el árbol y con los albergues" do
      c = actor(:coordinador)

      assert Emergencias.registrar_sector(c, "centro", "sector_1", "X", "bajo") ==
               {:error, {:id_duplicado, "sector_1"}}

      assert Emergencias.registrar_zona(c, "A01", "X", "bajo") == {:error, {:id_duplicado, "A01"}}
    end

    test "estado general y estadísticas acumuladas" do
      c = actor(:coordinador)
      necesidad!("agua", 10, "alta", "punto_s3")
      recurso!("R1", "agua", 100)
      {:ok, _} = Emergencias.actualizar_zona(c, "sector_3", %{"personas" => "700"})

      {:ok, estado} = Emergencias.estado_zona(c, "centro")
      assert length(estado.necesidades_abiertas) == 1
      assert [%{codigo: "albergue_2"}] = estado.albergues

      {:ok, stats} = Emergencias.estadisticas_zona(c, "centro")
      assert stats.totales.personas_afectadas == 1200 + 400 + 700
      assert stats.totales.necesidades_abiertas == 1
      assert stats.totales.recursos == 1
      assert stats.totales.albergues == 1
    end

    test "se rechazan niveles inválidos" do
      assert {:error, {:opcion_invalida, :nivel, _}} =
               Emergencias.registrar_zona(actor(:coordinador), "z9", "Z", "terrible")
    end
  end

  describe "necesidades y recursos" do
    setup do: con_demo()

    test "la zona de una necesidad debe existir" do
      assert {:error, {:zona_no_registrada, "marte"}} =
               Emergencias.registrar_necesidad(actor(:ciudadano), %{
                 tipo: "agua",
                 cantidad: 1,
                 prioridad: "alta",
                 zona: "marte"
               })
    end

    test "asignar, atender y cerrar; una necesidad cerrada no consume recursos" do
      c = actor(:coordinador)
      n = necesidad!("agua", 30, "critica")
      recurso!("R1", "agua", 50)

      assert {:ok, %{plan: [{"R1", 30}]}} = Emergencias.asignar_recurso(c, n.id, "agua", 30)
      {:ok, _} = Emergencias.atender_necesidad(c, n.id)
      {:ok, cerrada} = Emergencias.cerrar_necesidad(c, n.id)
      assert cerrada.estado == :atendida

      assert Emergencias.asignar_recurso(c, n.id, "agua", 1) == {:error, {:ya_cerrado, :atendida}}
      assert Emergencias.cerrar_necesidad(c, n.id) == {:error, {:ya_cerrado, :atendida}}
      assert {:ok, %{cantidad: 20}} = Inventario.obtener("R1")
    end

    test "listar por filtros ordena por prioridad" do
      c = actor(:coordinador)
      necesidad!("agua", 1, "baja", "sector_1")
      necesidad!("alimentos", 1, "critica", "centro_acopio_1")
      necesidad!("agua", 1, "alta", "zona_norte")

      {:ok, lista} = Emergencias.listar_necesidades(c, %{"zona" => "centro"})
      assert Enum.map(lista, & &1.prioridad) == [:critica, :baja]

      {:ok, [n]} = Emergencias.listar_necesidades(c, %{"tipo" => "agua", "prioridad" => "alta"})
      assert n.zona == "zona_norte"

      assert {:error, {:filtro_desconocido, "color", _}} =
               Emergencias.listar_necesidades(c, %{"color" => "x"})
    end

    test "despacho por prioridad: las críticas reciben primero" do
      c = actor(:coordinador)
      baja = necesidad!("agua", 40, "baja")
      critica = necesidad!("agua", 40, "critica")
      recurso!("R1", "agua", 50)

      {:ok, resultados} = Emergencias.despachar_necesidades(c)
      por_id = Map.new(resultados, fn {_, n, _} -> {n.id, n} end)
      assert por_id[critica.id].asignada == 40
      assert por_id[baja.id].asignada == 10
    end

    test "entradas, salidas, historial y no negativos" do
      c = actor(:coordinador)
      recurso!("R1", "agua", 10)
      {:ok, _} = Emergencias.entrada_recurso(c, "R1", 5, "donación")
      assert Emergencias.salida_recurso(c, "R1", 16) == {:error, {:inventario_insuficiente, 15}}
      assert Emergencias.entrada_recurso(c, "R1", -3) == {:error, {:debe_ser_positivo, :cantidad}}
      {:ok, %{cantidad: 0}} = Emergencias.salida_recurso(c, "R1", 15)

      {:ok, historial} = Emergencias.historial_recurso(c, "R1")
      assert Enum.map(historial, & &1.tipo) == [:registro, :entrada, :salida]
      assert Enum.map(historial, & &1.saldo) == [10, 15, 0]
    end

    test "transferencias entre centros de apoyo" do
      c = actor(:coordinador)
      recurso!("R001", "agua", 200)

      {:ok, t} = Emergencias.transferir_recurso(c, "R001", "centro_acopio_1", "albergue_2", 30)

      assert {t.origen.cantidad, t.destino.cantidad, t.destino.ubicacion} ==
               {170, 30, "albergue_2"}

      assert t.nuevo_recurso

      {:ok, t2} = Emergencias.transferir_recurso(c, "R001", "centro_acopio_1", "albergue_2", 20)

      assert {t2.destino.codigo, t2.destino.cantidad, t2.nuevo_recurso} ==
               {t.destino.codigo, 50, false}

      assert {:error, {:origen_incorrecto, "centro_acopio_1"}} =
               Emergencias.transferir_recurso(c, "R001", "otro", "albergue_2", 1)

      assert {:error, {:inventario_insuficiente, 150}} =
               Emergencias.transferir_recurso(c, "R001", "centro_acopio_1", "A01", 151)

      {:ok, disp} = Emergencias.disponibilidad(c, "agua", "centro")
      assert disp.total == 200
      {:ok, disp_norte} = Emergencias.disponibilidad(c, "agua", "zona_norte")
      assert disp_norte.total == 0
    end

    test "registro de recurso: ubicación válida y código único" do
      c = actor(:coordinador)
      recurso!("R1", "agua", 1)

      assert {:error, {:ubicacion_no_registrada, "luna"}} =
               Emergencias.registrar_recurso(c, %{
                 codigo: "R2",
                 nombre: "agua",
                 cantidad: 1,
                 unidad: "l",
                 ubicacion: "luna"
               })

      assert {:error, {:id_duplicado, "R1"}} =
               Emergencias.registrar_recurso(c, %{
                 codigo: "R1",
                 nombre: "agua",
                 cantidad: 1,
                 unidad: "l",
                 ubicacion: "A01"
               })
    end

    test "recursos críticos por demanda y por umbral" do
      c = actor(:coordinador)
      necesidad!("medicamentos", 100, "critica")
      recurso!("M1", "medicamentos", 30)
      recurso!("R1", "agua", 5)

      {:ok, criticos} = Emergencias.recursos_criticos(c)
      assert [%{tipo: "medicamentos", disponible: 30, demanda: 100}] = criticos.por_demanda
      assert [%{recurso: %{codigo: "R1"}}] = criticos.por_umbral
    end
  end

  describe "familiares" do
    setup do: con_demo()

    test "registro, búsqueda, transiciones e historial" do
      v = actor(:voluntario)

      {:ok, p} =
        Emergencias.reportar_persona(v, %{
          documento: "1001",
          nombre: "Andrés Pérez",
          zona: "zona_norte",
          estado: "reportada",
          edad: "34",
          familia: "Perez"
        })

      assert p.familia == "perez"

      assert {:error, {:id_duplicado, "1001"}} =
               Emergencias.reportar_persona(v, %{
                 documento: "1001",
                 nombre: "Otro",
                 zona: "centro"
               })

      {:ok, [encontrada]} = Emergencias.buscar_personas(v, %{"nombre" => "andres"})
      assert encontrada.documento == "1001"
      {:ok, []} = Emergencias.buscar_personas(v, %{"estado" => "localizada"})

      {:ok, _} = Emergencias.actualizar_persona(v, "1001", "localizada")
      {:ok, _} = Emergencias.actualizar_persona(v, "1001", "reunificada")

      assert Emergencias.actualizar_persona(v, "1001", "localizada") ==
               {:error, {:ya_cerrado, :reunificada}}

      {:ok, historial} = Emergencias.historial_persona(v, "1001")

      assert Enum.map(historial, fn {_, _, hacia, _, _} -> hacia end) == [
               :reunificada,
               :localizada,
               :reportada
             ]
    end

    test "mensajes a persona y a familia, con estado" do
      v = actor(:voluntario)

      {:ok, _} =
        Emergencias.reportar_persona(v, %{
          documento: "1001",
          nombre: "Andrés",
          zona: "centro",
          familia: "perez"
        })

      {:ok, m1} = Emergencias.enviar_mensaje(actor(:ciudadano, "maria"), "1001", "Estoy bien")
      {:ok, _} = Emergencias.enviar_mensaje(v, "familia:Perez", "Reunión en A01")

      assert {m1.remitente, m1.estado} == {"maria", :pendiente}
      {:ok, mensajes} = Emergencias.mensajes_familia(v, "1001")
      assert length(mensajes) == 2

      {:ok, entregado} = Emergencias.marcar_mensaje(v, m1.id, "entregado")
      assert entregado.estado == :entregado

      assert Emergencias.marcar_mensaje(v, m1.id, "entregado") ==
               {:error, {:mismo_estado, :entregado}}

      assert {:error, {:no_encontrado, "999"}} = Emergencias.enviar_mensaje(v, "999", "hola")
    end
  end

  describe "mascotas" do
    setup do: con_demo()

    test "coincidencias, confirmación y cierre único" do
      v = actor(:voluntario)

      base = %{
        especie: "perro",
        color: "negra",
        tamano: "mediana",
        zona: "zona_norte",
        contacto: "300"
      }

      {:ok, perdida} =
        Emergencias.reportar_mascota(v, Map.merge(base, %{tipo_reporte: "lost", nombre: "Luna"}))

      {:ok, _gato} =
        Emergencias.reportar_mascota(
          v,
          Map.merge(base, %{tipo_reporte: "found", especie: "gato", nombre: "?"})
        )

      {:ok, encontrada} =
        Emergencias.reportar_mascota(
          v,
          Map.merge(base, %{tipo_reporte: "found", nombre: "desconocido"})
        )

      {:ok, [coincidencia]} = Emergencias.buscar_coincidencias(v)
      assert {coincidencia.perdida, coincidencia.encontrada} == {perdida.id, encontrada.id}

      {:ok, posibles} = Emergencias.listar_mascotas(v, %{"estado" => "posible_coincidencia"})
      assert length(posibles) == 2

      {:ok, _} = Emergencias.confirmar_coincidencia(v, perdida.id, encontrada.id)

      assert Emergencias.confirmar_coincidencia(v, perdida.id, encontrada.id) ==
               {:error, {:ya_cerrado, :resuelta}}

      {:ok, resueltas} =
        Emergencias.listar_mascotas(v, %{"estado" => "resuelta", "especie" => "PERRO"})

      assert length(resueltas) == 2
      assert {:ok, []} = Emergencias.buscar_coincidencias(v)
    end

    test "no se confirman dos reportes del mismo tipo" do
      v = actor(:voluntario)

      base = %{
        tipo_reporte: "lost",
        especie: "perro",
        nombre: "x",
        color: "negro",
        tamano: "grande",
        zona: "centro",
        contacto: "1"
      }

      {:ok, a} = Emergencias.reportar_mascota(v, base)
      {:ok, b} = Emergencias.reportar_mascota(v, base)
      assert Emergencias.confirmar_coincidencia(v, a.id, b.id) == {:error, :mismo_tipo_de_reporte}
    end
  end

  describe "albergues" do
    setup do: con_demo()

    test "ingreso actualiza a la persona, capacidad y reporte de ocupación" do
      c = actor(:coordinador)

      {:ok, _} =
        Emergencias.registrar_albergue(c, %{
          codigo: "A02",
          nombre: "Pequeño",
          zona: "norte_1",
          capacidad: "1"
        })

      {:ok, _} =
        Emergencias.reportar_persona(c, %{
          documento: "1001",
          nombre: "Andrés",
          zona: "zona_norte",
          estado: "localizada"
        })

      {:ok, %{nota: :persona_actualizada}} = Emergencias.registrar_ingreso(c, "A02", "1001")
      {:ok, persona} = Emergencias.buscar_persona(c, "1001")
      assert persona.estado == :en_albergue

      assert Emergencias.registrar_ingreso(c, "A02", "2002") == {:error, {:capacidad_superada, 1}}

      assert Emergencias.registrar_ingreso(c, "A01", "1001") ==
               {:error, {:ya_esta_en_otro_albergue, "A02"}}

      {:ok, [primero | _]} = Emergencias.reporte_albergues(c, 3)
      assert primero.codigo == "A02"

      {:ok, disponibles} = Emergencias.albergues_disponibles(c)
      refute Enum.any?(disponibles, &(&1.codigo == "A02"))

      {:ok, _} = Emergencias.registrar_salida(c, "A02", "1001")

      assert Emergencias.registrar_salida(c, "A02", "1001") ==
               {:error, {:no_esta_en_albergue, "1001"}}
    end

    test "consultar albergue muestra recursos y necesidades asociados" do
      c = actor(:coordinador)
      recurso!("R1", "agua", 10, "A01")

      {:ok, _} =
        Emergencias.registrar_necesidad(c, %{
          tipo: "alimentos",
          cantidad: 5,
          prioridad: "alta",
          zona: "zona_norte",
          asociado_a: "albergue:A01"
        })

      {:ok, info} = Emergencias.consultar_albergue(c, "A01")
      assert {info.cupos, length(info.recursos), length(info.necesidades)} == {150, 1, 1}

      assert {:error, {:no_encontrado, "A99"}} =
               Emergencias.registrar_necesidad(c, %{
                 tipo: "agua",
                 cantidad: 1,
                 prioridad: "alta",
                 zona: "centro",
                 asociado_a: "albergue:A99"
               })
    end

    test "no se registra un albergue con capacidad negativa ni en zona inexistente" do
      c = actor(:coordinador)

      assert {:error, {:debe_ser_positivo, :capacidad}} =
               Emergencias.registrar_albergue(c, %{
                 codigo: "A9",
                 nombre: "X",
                 zona: "centro",
                 capacidad: "-1"
               })

      assert {:error, {:zona_no_registrada, "marte"}} =
               Emergencias.registrar_albergue(c, %{
                 codigo: "A9",
                 nombre: "X",
                 zona: "marte",
                 capacidad: "10"
               })
    end
  end

  test "resumen global consulta todos los módulos" do
    con_demo()
    c = actor(:coordinador)
    recurso!("R1", "agua", 50)
    necesidad!("agua", 30, "critica")

    {:ok, r} = Emergencias.resumen(c)
    assert r.zonas == 2
    assert r.recursos_por_tipo == [{"agua", 50, "unidades"}]
    assert r.pendientes_por_prioridad == %{critica: 1}
    assert r.albergues == 2
  end
end
