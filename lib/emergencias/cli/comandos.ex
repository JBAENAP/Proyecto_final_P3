defmodule Emergencias.CLI.Comandos do
  @moduledoc """
  Traduce cada comando de consola a una llamada de la fachada `Emergencias`
  (a través de `CLI.Remoto`, que la ejecuta en el servidor cuando la terminal es
  un nodo cliente) y da formato al resultado. No contiene lógica de negocio.

  El estado de la consola es `%{sesion: pid | nil}`; el pid de la sesión puede
  estar en el nodo servidor. El usuario conectado se consulta en cada comando al
  proceso de sesión (así un cambio de rol hecho por un administrador se aplica de
  inmediato).
  """

  alias Emergencias.CLI.{Formato, Parser, Remoto}
  alias Emergencias.Dominio.Albergue
  alias Emergencias.{Permisos, Validacion}

  # {comando, permiso requerido (nil = libre), sintaxis, descripción}
  @ayuda [
    {"Sesión", nil, nil, nil},
    {"connect", nil, "connect usuario clave [tipo] [zona] [\"Nombre completo\"]",
     "Conecta; si el usuario no existe lo registra (tipos: ciudadano, voluntario, coordinador, administrador)"},
    {"disconnect", nil, "disconnect", "Cierra la sesión"},
    {"whoami", nil, "whoami", "Muestra el usuario conectado"},
    {"activity", :activity, "activity [usuario]",
     "Actividad registrada (la de otros solo administrador)"},
    {"list_users", :list_users, "list_users", "Usuarios registrados y conectados"},
    {"set_role", :set_role, "set_role usuario tipo", "Cambia el tipo de un usuario"},
    {"Zonas", nil, nil, nil},
    {"register_zone", :register_zone, "register_zone codigo \"nombre\" nivel [personas]",
     "Registra una zona (nivel: critico, alto, medio, bajo)"},
    {"register_sector", :register_sector,
     "register_sector zona codigo \"nombre\" nivel [personas]",
     "Registra un sector dentro de una zona"},
    {"register_point", :register_point, "register_point sector codigo \"nombre\" [categoria]",
     "Registra un punto de atención / centro de acopio en un sector"},
    {"update_zone", :update_zone, "update_zone codigo [nivel=..] [personas=..]",
     "Actualiza afectación"},
    {"list_zones", :list_zones, "list_zones", "Árbol de zonas, sectores y puntos"},
    {"zone_status", :zone_status, "zone_status codigo", "Estado general de una zona"},
    {"zone_stats", :zone_stats, "zone_stats codigo",
     "Estadísticas acumuladas de la zona y sus sectores"},
    {"Necesidades", nil, nil, nil},
    {"register_need", :register_need,
     "register_need tipo cantidad prioridad zona \"descripcion\" [para=albergue:A01|persona:DOC|familia:X]",
     "Registra una necesidad (tipos: agua, alimentos, medicamentos, primeros_auxilios, refugio, transporte, rescate, otra)"},
    {"list_needs", :list_needs, "list_needs [zona=..] [tipo=..] [prioridad=..] [estado=..]",
     "Necesidades ordenadas por prioridad"},
    {"pending_needs", :pending_needs, "pending_needs", "Necesidades abiertas por prioridad"},
    {"assign_resource", :assign_resource, "assign_resource N001 tipo cantidad [desde=R001]",
     "Asigna recursos a una necesidad (todo o nada)"},
    {"attend_need", :attend_need, "attend_need N001", "Pasa la necesidad a 'en atención'"},
    {"close_need", :close_need, "close_need N001", "Marca la necesidad como atendida"},
    {"cancel_need", :cancel_need, "cancel_need N001", "Cancela la necesidad"},
    {"dispatch_needs", :dispatch_needs, "dispatch_needs",
     "Reparte el inventario disponible por prioridad"},
    {"Recursos", nil, nil, nil},
    {"register_resource", :register_resource,
     "register_resource codigo nombre cantidad unidad ubicacion [categoria]",
     "Registra un recurso"},
    {"list_resources", :list_resources, "list_resources [tipo=..] [zona=..] [ubicacion=..]",
     "Inventario"},
    {"resource_in", :resource_in, "resource_in codigo cantidad [\"referencia\"]",
     "Entrada de inventario"},
    {"resource_out", :resource_out, "resource_out codigo cantidad [\"referencia\"]",
     "Salida de inventario"},
    {"availability", :availability, "availability tipo [zona]", "Disponibilidad por tipo y zona"},
    {"transfer_resource", :transfer_resource, "transfer_resource codigo origen destino cantidad",
     "Transfiere entre centros de apoyo"},
    {"resource_history", :resource_history, "resource_history [codigo]",
     "Historial de movimientos"},
    {"critical_resources", :critical_resources, "critical_resources",
     "Recursos insuficientes o bajo umbral"},
    {"Familiares", nil, nil, nil},
    {"report_person", :report_person,
     "report_person documento \"nombre\" zona estado [edad] [familia]",
     "Registra una persona (estados: sin_informacion, reportada, localizada, trasladada, en_albergue, reunificada)"},
    {"update_person", :update_person, "update_person documento estado [\"detalle\"]",
     "Cambia el estado"},
    {"find_person", :find_person, "find_person documento", "Busca una persona por documento"},
    {"search_persons", :search_persons,
     "search_persons [nombre=..] [zona=..] [estado=..] [familia=..]", "Busca personas"},
    {"person_history", :person_history, "person_history documento",
     "Historial de estados de una persona"},
    {"send_family_message", :send_family_message,
     "send_family_message documento|familia:X \"mensaje\"", "Deja un mensaje"},
    {"list_family_messages", :list_family_messages, "list_family_messages documento|familia:X",
     "Mensajes de una persona y su familia"},
    {"mark_message", :mark_message, "mark_message M001 entregado|pendiente",
     "Cambia el estado de un mensaje"},
    {"Mascotas", nil, nil, nil},
    {"report_pet", :report_pet,
     "report_pet lost|found especie \"nombre\" color tamaño zona contacto [\"caracteristicas\"]",
     "Reporta mascota perdida o encontrada (nombre 'desconocido' si no se sabe)"},
    {"list_pets", :list_pets, "list_pets [especie=..] [zona=..] [estado=..] [tipo=..]",
     "Reportes de mascotas"},
    {"match_pets", :match_pets, "match_pets", "Calcula posibles coincidencias (puntaje 0-100)"},
    {"confirm_match", :confirm_match, "confirm_match PET001 PET002",
     "Confirma coincidencia y cierra ambos"},
    {"Albergues", nil, nil, nil},
    {"register_shelter", :register_shelter,
     "register_shelter codigo \"nombre\" zona capacidad [ocupacion]", "Registra un albergue"},
    {"check_shelter", :check_shelter, "check_shelter codigo",
     "Cupos, recursos y necesidades del albergue"},
    {"register_entry", :register_entry, "register_entry codigo documento",
     "Ingreso de una persona"},
    {"register_exit", :register_exit, "register_exit codigo documento", "Salida de una persona"},
    {"list_shelters", :list_shelters, "list_shelters", "Todos los albergues"},
    {"shelters_available", :shelters_available, "shelters_available", "Albergues con cupo"},
    {"shelter_report", :shelter_report, "shelter_report [n]", "Albergues con mayor ocupación"},
    {"General", nil, nil, nil},
    {"summary", :summary, "summary", "Resumen global de la emergencia"},
    {"simulate_conflict", :simulate_conflict,
     "simulate_conflict ubicacion [stock] [pedido1,pedido2,..]",
     "Demuestra el conflicto concurrente (por defecto 50 L con pedidos de 30 y 25)"},
    {"load_demo", :load_demo, "load_demo",
     "Carga zonas, sectores, puntos y albergues de ejemplo"},
    {"help", nil, "help [comando]", "Ayuda"},
    {"exit", nil, "exit", "Sale de la consola"}
  ]

  @sintaxis for {c, _, s, _} <- @ayuda, s != nil, into: %{}, do: {c, s}
  @permisos for {c, p, s, _} <- @ayuda, s != nil, into: %{}, do: {c, p}

  @doc "Permiso que exige un comando (`nil` si es libre). Lo usa el menú para filtrar opciones."
  def permiso(comando), do: Map.get(@permisos, comando)

  # ---------------------------------------------------------------------------
  # Entrada principal
  # ---------------------------------------------------------------------------

  def estado_inicial, do: %{sesion: nil}

  @doc "Ejecuta una línea y devuelve `{nuevo_estado, texto_de_salida}`."
  def ejecutar(linea, estado) do
    {estado, aviso} = verificar_sesion(estado)

    {estado, salida} =
      case Parser.parsear(linea) do
        {:ok, :vacio} -> {estado, ""}
        {:ok, %{comando: c, args: a, opciones: o}} -> despachar(c, a, o, estado)
        {:error, motivo} -> {estado, Formato.error(motivo)}
      end

    {estado, Enum.join(Enum.reject([aviso, salida], &(&1 == "")), "\n")}
  end

  @doc "Ejecuta varias líneas seguidas y devuelve `{salidas, estado_final}`."
  def ejecutar_lineas(lineas, estado \\ estado_inicial()) do
    Enum.map_reduce(lineas, estado, fn linea, acumulado ->
      {nuevo, salida} = ejecutar(linea, acumulado)
      {salida, nuevo}
    end)
  end

  @doc "Usuario de la sesión actual (o nil)."
  def usuario_actual(%{sesion: sesion}), do: Remoto.usuario_sesion(sesion)

  # Si el proceso de sesión ya no existe (desconexión, caída del servidor), la consola
  # queda desconectada. El pid puede ser de otro nodo, por eso se consulta con una
  # llamada en vez de Process.alive?/1 (que solo sirve para procesos locales).
  defp verificar_sesion(%{sesion: nil} = estado), do: {estado, ""}

  defp verificar_sesion(estado) do
    case usuario_actual(estado) do
      nil -> {%{estado | sesion: nil}, Formato.error(:sesion_perdida)}
      _usuario -> {estado, ""}
    end
  end

  defp despachar("help", args, _opciones, estado),
    do: {estado, ayuda(args, usuario_actual(estado))}

  defp despachar("connect", _args, _opciones, %{sesion: s} = estado) when s != nil,
    do: {estado, Formato.error(:sesion_activa)}

  defp despachar("connect", [usuario, clave | resto], _opciones, estado) do
    [tipo, zona, nombre] = completar(resto, 3)

    # Se envía el pid de esta consola: la sesión (que vive en el servidor) lo
    # monitorea y se cierra sola si la consola o su nodo terminan.
    case Remoto.conectar(usuario, clave, tipo, zona, nombre, self()) do
      {:ok, %{usuario: u, sesion: sesion, modo: modo}} ->
        accion =
          if modo == :registrado,
            do: "Usuario registrado y conectado",
            else: "Bienvenido de nuevo"

        {%{estado | sesion: sesion},
         Formato.ok(
           "#{accion}: #{u.nombre_completo} (#{u.username}) - #{Formato.etiqueta(u.tipo)} - zona #{u.zona}"
         )}

      error ->
        {estado, Formato.error(error)}
    end
  end

  defp despachar("connect", _args, _opciones, estado),
    do: {estado, Formato.error({:uso, @sintaxis["connect"]})}

  defp despachar(comando, _args, _opciones, %{sesion: nil} = estado) do
    if Map.has_key?(@sintaxis, comando),
      do: {estado, Formato.error(:no_conectado)},
      else: {estado, Formato.error({:comando_desconocido, comando})}
  end

  defp despachar("disconnect", _args, _opciones, %{sesion: sesion} = estado) do
    case Remoto.desconectar(sesion) do
      {:ok, usuario} ->
        {%{estado | sesion: nil}, Formato.ok("Sesión de #{usuario.username} cerrada")}

      error ->
        {%{estado | sesion: nil}, Formato.error(error)}
    end
  end

  defp despachar(comando, args, opciones, %{sesion: sesion} = estado) do
    case Remoto.usuario_sesion(sesion) do
      nil ->
        {%{estado | sesion: nil}, Formato.error(:sesion_perdida)}

      actor ->
        Remoto.contar_comando(sesion)

        salida =
          try do
            correr(comando, args, opciones, actor)
          rescue
            excepcion -> Formato.error("fallo inesperado: " <> Exception.message(excepcion))
          end

        {estado, salida}
    end
  end

  # ---------------------------------------------------------------------------
  # Comandos (requieren sesión)
  # ---------------------------------------------------------------------------

  defp correr("whoami", _, _, u) do
    "#{u.nombre_completo} (#{u.username}) - #{Formato.etiqueta(u.tipo)} - zona #{u.zona}\n" <>
      "Usuarios conectados: #{Enum.join(Remoto.conectados(), ", ")}"
  end

  defp correr("activity", args, _, u) do
    responder(Remoto.actividad(u, List.first(args)), fn entradas ->
      Formato.tabla(
        ["FECHA", "USUARIO", "ACCION", "DETALLE", "RESULTADO"],
        Enum.map(entradas, fn {f, us, a, d, r} -> [f, us, a, d, r] end)
      )
    end)
  end

  defp correr("list_users", _, _, u) do
    responder(Remoto.listar_usuarios(u), fn lista ->
      Formato.tabla(
        ["USUARIO", "NOMBRE", "TIPO", "ZONA", "CONECTADO"],
        Enum.map(lista, fn {x, conectado} ->
          [x.username, x.nombre_completo, x.tipo, x.zona, if(conectado, do: "si", else: "no")]
        end)
      )
    end)
  end

  defp correr("set_role", [usuario, tipo], _, u) do
    responder(
      Remoto.cambiar_rol(u, usuario, tipo),
      &Formato.ok("#{&1.username} ahora es #{Formato.etiqueta(&1.tipo)}")
    )
  end

  # --- Zonas -----------------------------------------------------------------

  defp correr("register_zone", [codigo, nombre, nivel | resto], _, u) do
    responder(
      Remoto.registrar_zona(u, codigo, nombre, nivel, List.first(resto)),
      &Formato.ok("Zona #{&1.codigo} registrada")
    )
  end

  defp correr("register_sector", [zona, codigo, nombre, nivel | resto], _, u) do
    responder(
      Remoto.registrar_sector(u, zona, codigo, nombre, nivel, List.first(resto)),
      &Formato.ok("Sector #{&1.codigo} registrado en #{zona}")
    )
  end

  defp correr("register_point", [sector, codigo, nombre | resto], _, u) do
    responder(
      Remoto.registrar_punto(u, sector, codigo, nombre, List.first(resto) || "atencion"),
      &Formato.ok("Punto #{&1.codigo} (#{&1.categoria}) registrado en #{sector}")
    )
  end

  defp correr("update_zone", [codigo], opciones, u) when map_size(opciones) > 0 do
    responder(
      Remoto.actualizar_zona(u, codigo, opciones),
      &Formato.ok("#{&1.codigo}: nivel #{Formato.etiqueta(&1.nivel)}, personas #{&1.personas}")
    )
  end

  defp correr("list_zones", _, _, u) do
    responder(Remoto.listar_zonas(u), fn
      [] ->
        "(no hay zonas registradas; use register_zone o load_demo)"

      nodos ->
        Enum.map_join(nodos, "\n", fn {profundidad, n} ->
          detalle =
            case n.tipo do
              :punto -> "punto - #{n.categoria}"
              tipo -> "#{tipo} - nivel #{Formato.etiqueta(n.nivel)} - #{n.personas} personas"
            end

          String.duplicate("   ", profundidad) <> "#{n.codigo}: #{n.nombre} (#{detalle})"
        end)
    end)
  end

  defp correr("zone_status", [codigo], _, u) do
    responder(Remoto.estado_zona(u, codigo), fn e ->
      n = e.nodo

      [
        Formato.titulo("#{n.nombre} (#{n.codigo})"),
        "Ruta: #{Enum.join(e.ruta, " > ")}",
        "Tipo: #{n.tipo}  Nivel de afectación: #{Formato.etiqueta(n.nivel)}  Personas afectadas (estimado propio): #{n.personas}",
        "Personas reportadas: #{e.personas}  Mascotas activas: #{e.mascotas_activas}",
        "\nAlbergues:",
        tabla_albergues(e.albergues),
        "\nNecesidades abiertas (por prioridad):",
        tabla_necesidades(e.necesidades_abiertas),
        "\nRecursos:",
        tabla_recursos(e.recursos)
      ]
      |> Enum.join("\n")
    end)
  end

  defp correr("zone_stats", [codigo], _, u) do
    responder(Remoto.estadisticas_zona(u, codigo), fn estadisticas ->
      Formato.titulo("Estadísticas acumuladas de #{codigo}") <>
        "\n" <> arbol_estadisticas(estadisticas, 0)
    end)
  end

  # --- Necesidades -----------------------------------------------------------

  defp correr("register_need", [tipo, cantidad, prioridad, zona | descripcion], opciones, u) do
    attrs = %{
      tipo: tipo,
      cantidad: cantidad,
      prioridad: prioridad,
      zona: zona,
      descripcion: Enum.join(descripcion, " "),
      asociado_a: opciones["para"]
    }

    responder(
      Remoto.registrar_necesidad(u, attrs),
      &Formato.ok(
        "Necesidad #{&1.id} registrada: #{&1.cantidad} de #{&1.tipo}, prioridad #{&1.prioridad}, zona #{&1.zona}"
      )
    )
  end

  defp correr("list_needs", _, opciones, u),
    do: responder(Remoto.listar_necesidades(u, opciones), &tabla_necesidades/1)

  defp correr("pending_needs", _, _, u),
    do: responder(Remoto.necesidades_pendientes(u), &tabla_necesidades/1)

  defp correr("assign_resource", [id, tipo, cantidad], opciones, u) do
    opciones = if opciones["desde"], do: [desde: opciones["desde"]], else: []

    responder(Remoto.asignar_recurso(u, id, tipo, cantidad, opciones), fn %{
                                                                            necesidad: n,
                                                                            plan: plan
                                                                          } ->
      Formato.ok(
        "Asignado a #{n.id}: #{plan_texto(plan)}. Cubierto #{n.asignada}/#{n.cantidad} - estado #{Formato.etiqueta(n.estado)}"
      )
    end)
  end

  defp correr("attend_need", [id], _, u),
    do: responder(Remoto.atender_necesidad(u, id), &estado_necesidad/1)

  defp correr("close_need", [id], _, u),
    do: responder(Remoto.cerrar_necesidad(u, id), &estado_necesidad/1)

  defp correr("cancel_need", [id], _, u),
    do: responder(Remoto.cancelar_necesidad(u, id), &estado_necesidad/1)

  defp correr("dispatch_needs", _, _, u) do
    responder(Remoto.despachar_necesidades(u), fn resultados ->
      Formato.tabla(
        ["NECESIDAD", "PRIORIDAD", "TIPO", "RESULTADO", "CUBIERTO"],
        Enum.map(resultados, fn
          {:asignada, n, plan} ->
            [
              n.id,
              n.prioridad,
              n.tipo,
              "asignado " <> plan_texto(plan),
              "#{n.asignada}/#{n.cantidad}"
            ]

          {:sin_asignar, n, motivo} ->
            [
              n.id,
              n.prioridad,
              n.tipo,
              Formato.mensaje_error(motivo),
              "#{n.asignada}/#{n.cantidad}"
            ]
        end)
      )
    end)
  end

  # --- Recursos --------------------------------------------------------------

  defp correr("register_resource", [codigo, nombre, cantidad, unidad, ubicacion | resto], _, u) do
    attrs = %{
      codigo: codigo,
      nombre: nombre,
      cantidad: cantidad,
      unidad: unidad,
      ubicacion: ubicacion,
      categoria: List.first(resto)
    }

    responder(
      Remoto.registrar_recurso(u, attrs),
      &Formato.ok(
        "Recurso #{&1.codigo} registrado: #{&1.cantidad} #{&1.unidad} de #{&1.nombre} en #{&1.ubicacion} (zona #{&1.zona})"
      )
    )
  end

  defp correr("list_resources", _, opciones, u),
    do: responder(Remoto.listar_recursos(u, opciones), &tabla_recursos/1)

  defp correr("resource_in", [codigo, cantidad | ref], _, u) do
    responder(
      Remoto.entrada_recurso(u, codigo, cantidad, Enum.join(ref, " ")),
      &Formato.ok("#{&1.codigo}: nuevo saldo #{&1.cantidad} #{&1.unidad}")
    )
  end

  defp correr("resource_out", [codigo, cantidad | ref], _, u) do
    responder(
      Remoto.salida_recurso(u, codigo, cantidad, Enum.join(ref, " ")),
      &Formato.ok("#{&1.codigo}: nuevo saldo #{&1.cantidad} #{&1.unidad}")
    )
  end

  defp correr("availability", [tipo | resto], _, u) do
    responder(Remoto.disponibilidad(u, tipo, List.first(resto)), fn d ->
      "Disponible de '#{d.tipo}'#{if d.zona, do: " en #{d.zona}", else: ""}: #{d.total}\n" <>
        tabla_recursos(d.recursos)
    end)
  end

  defp correr("transfer_resource", [codigo, origen, destino, cantidad], _, u) do
    responder(Remoto.transferir_recurso(u, codigo, origen, destino, cantidad), fn r ->
      Formato.ok(
        "Transferidas #{cantidad} unidades. #{r.origen.codigo} (#{origen}) queda con #{r.origen.cantidad}; " <>
          "#{r.destino.codigo} (#{destino}) queda con #{r.destino.cantidad}" <>
          if(r.nuevo_recurso, do: " [recurso nuevo]", else: "")
      )
    end)
  end

  defp correr("resource_history", args, _, u) do
    responder(Remoto.historial_recurso(u, List.first(args)), fn movimientos ->
      Formato.tabla(
        ["FECHA", "TIPO", "RECURSO", "CANTIDAD", "SALDO", "REFERENCIA", "USUARIO"],
        Enum.map(
          movimientos,
          &[&1.fecha, &1.tipo, &1.codigo, &1.cantidad, &1.saldo, &1.referencia, &1.usuario]
        )
      )
    end)
  end

  defp correr("critical_resources", _, _, u) do
    responder(Remoto.recursos_criticos(u), fn c ->
      [
        Formato.titulo("Tipos con demanda mayor que la existencia"),
        Formato.tabla(
          ["TIPO", "DISPONIBLE", "DEMANDA ABIERTA", "FALTANTE"],
          Enum.map(
            c.por_demanda,
            &[&1.tipo, &1.disponible, &1.demanda, &1.demanda - &1.disponible]
          )
        ),
        Formato.titulo("Recursos en o bajo el umbral crítico"),
        Formato.tabla(
          ["CODIGO", "NOMBRE", "CANTIDAD", "UMBRAL", "UBICACION"],
          Enum.map(
            c.por_umbral,
            &[
              &1.recurso.codigo,
              &1.recurso.nombre,
              &1.recurso.cantidad,
              &1.umbral,
              &1.recurso.ubicacion
            ]
          )
        )
      ]
      |> Enum.join("\n")
    end)
  end

  # --- Familiares ------------------------------------------------------------

  defp correr("report_person", [documento, nombre, zona, estado | resto], _, u) do
    [edad, familia] = completar(resto, 2)

    attrs = %{
      documento: documento,
      nombre: nombre,
      zona: zona,
      estado: estado,
      edad: edad,
      familia: familia
    }

    responder(
      Remoto.reportar_persona(u, attrs),
      &Formato.ok(
        "Persona #{&1.id} registrada: #{&1.nombre} (#{&1.documento}) - #{Formato.etiqueta(&1.estado)}"
      )
    )
  end

  defp correr("update_person", [documento, estado | detalle], _, u) do
    responder(
      Remoto.actualizar_persona(u, documento, estado, Enum.join(detalle, " ")),
      &Formato.ok("#{&1.nombre} ahora está #{Formato.etiqueta(&1.estado)}")
    )
  end

  defp correr("find_person", [documento], _, u) do
    responder(Remoto.buscar_persona(u, documento), fn p ->
      [
        tabla_personas([p]),
        "Último cambio: #{Formato.fecha(p.actualizado_en)}",
        "Mensajes: use list_family_messages #{p.documento}"
      ]
      |> Enum.join("\n")
    end)
  end

  defp correr("search_persons", _, opciones, u),
    do: responder(Remoto.buscar_personas(u, opciones), &tabla_personas/1)

  defp correr("person_history", [documento], _, u) do
    responder(Remoto.historial_persona(u, documento), fn historial ->
      Formato.tabla(
        ["FECHA", "DESDE", "HACIA", "USUARIO", "DETALLE"],
        Enum.map(historial, fn {f, desde, hacia, us, d} -> [f, desde, hacia, us, d] end)
      )
    end)
  end

  defp correr("send_family_message", [destinatario | contenido], _, u) when contenido != [] do
    responder(
      Remoto.enviar_mensaje(u, destinatario, Enum.join(contenido, " ")),
      &Formato.ok("Mensaje #{&1.id} registrado para #{&1.destinatario}")
    )
  end

  defp correr("list_family_messages", [destinatario], _, u) do
    responder(Remoto.mensajes_familia(u, destinatario), fn mensajes ->
      Formato.tabla(
        ["ID", "FECHA", "DE", "PARA", "ESTADO", "MENSAJE"],
        Enum.map(
          mensajes,
          &[&1.id, &1.fecha, &1.remitente, &1.destinatario, &1.estado, &1.contenido]
        )
      )
    end)
  end

  defp correr("mark_message", [id, estado], _, u) do
    responder(
      Remoto.marcar_mensaje(u, id, estado),
      &Formato.ok("Mensaje #{&1.id}: #{Formato.etiqueta(&1.estado)}")
    )
  end

  # --- Mascotas --------------------------------------------------------------

  defp correr(
         "report_pet",
         [tipo, especie, nombre, color, tamano, zona, contacto | caracteristicas],
         _,
         u
       ) do
    attrs = %{
      tipo_reporte: tipo,
      especie: especie,
      nombre: nombre,
      color: color,
      tamano: tamano,
      zona: zona,
      contacto: contacto,
      caracteristicas: Enum.join(caracteristicas, " ")
    }

    responder(
      Remoto.reportar_mascota(u, attrs),
      &Formato.ok("Reporte #{&1.id} (#{Formato.etiqueta(&1.tipo_reporte)}) registrado")
    )
  end

  defp correr("list_pets", _, opciones, u) do
    responder(Remoto.listar_mascotas(u, opciones), fn lista ->
      Formato.tabla(
        [
          "ID",
          "REPORTE",
          "ESPECIE",
          "NOMBRE",
          "COLOR",
          "TAMAÑO",
          "ZONA",
          "ESTADO",
          "CONTACTO",
          "CON"
        ],
        Enum.map(
          lista,
          &[
            &1.id,
            &1.tipo_reporte,
            &1.especie,
            &1.nombre,
            &1.color,
            &1.tamano,
            &1.zona,
            &1.estado,
            &1.contacto,
            &1.coincidencia_con
          ]
        )
      )
    end)
  end

  defp correr("match_pets", _, _, u) do
    responder(Remoto.buscar_coincidencias(u), fn
      [] ->
        "No se encontraron posibles coincidencias"

      lista ->
        "Posibles coincidencias (especie 30, color 20, tamaño 15, zona 15, nombre 10, características 10):\n" <>
          Formato.tabla(
            ["PERDIDA", "ENCONTRADA", "PUNTAJE", "DETALLE"],
            Enum.map(lista, &[&1.perdida, &1.encontrada, &1.puntaje, Formato.conteos(&1.detalle)])
          ) <> "\nConfirme con: confirm_match PERDIDA ENCONTRADA"
    end)
  end

  defp correr("confirm_match", [a, b], _, u) do
    responder(Remoto.confirmar_coincidencia(u, a, b), fn [x, y] ->
      Formato.ok("Coincidencia confirmada: #{x.id} y #{y.id} quedan resueltos")
    end)
  end

  # --- Albergues -------------------------------------------------------------

  defp correr("register_shelter", [codigo, nombre, zona, capacidad | resto], _, u) do
    attrs = %{
      codigo: codigo,
      nombre: nombre,
      zona: zona,
      capacidad: capacidad,
      ocupacion: List.first(resto)
    }

    responder(
      Remoto.registrar_albergue(u, attrs),
      &Formato.ok("Albergue #{&1.codigo} registrado (capacidad #{&1.capacidad})")
    )
  end

  defp correr("check_shelter", [codigo], _, u) do
    responder(Remoto.consultar_albergue(u, codigo), fn c ->
      a = c.albergue

      [
        Formato.titulo("#{a.nombre} (#{a.codigo}) - zona #{a.zona}"),
        "Capacidad: #{a.capacidad}  Ocupación: #{a.ocupacion} (#{c.porcentaje}%)  Cupos disponibles: #{c.cupos}",
        "Personas registradas: #{a.ocupantes |> MapSet.to_list() |> Enum.join(", ")}",
        "\nRecursos en el albergue:",
        tabla_recursos(c.recursos),
        "\nNecesidades asociadas:",
        tabla_necesidades(c.necesidades)
      ]
      |> Enum.join("\n")
    end)
  end

  defp correr("register_entry", [codigo, documento], _, u) do
    responder(Remoto.registrar_ingreso(u, codigo, documento), fn %{albergue: a, nota: nota} ->
      extra =
        case nota do
          :persona_actualizada ->
            " La persona quedó en estado 'en albergue'."

          :persona_no_registrada ->
            " (La persona no está en el registro de familiares.)"

          {:estado_persona_sin_cambio, motivo} ->
            " (Estado de la persona sin cambio: #{Formato.mensaje_error(motivo)})"
        end

      Formato.ok(
        "Ingreso registrado en #{a.codigo}. Ocupación #{a.ocupacion}/#{a.capacidad}." <> extra
      )
    end)
  end

  defp correr("register_exit", [codigo, documento], _, u) do
    responder(
      Remoto.registrar_salida(u, codigo, documento),
      &Formato.ok("Salida registrada de #{&1.codigo}. Ocupación #{&1.ocupacion}/#{&1.capacidad}")
    )
  end

  defp correr("list_shelters", _, _, u),
    do: responder(Remoto.listar_albergues(u), &tabla_albergues/1)

  defp correr("shelters_available", _, _, u),
    do: responder(Remoto.albergues_disponibles(u), &tabla_albergues/1)

  defp correr("shelter_report", args, _, u) do
    responder(Remoto.reporte_albergues(u, List.first(args) || 5), fn lista ->
      "Albergues con mayor nivel de ocupación:\n" <> tabla_albergues(lista)
    end)
  end

  # --- General ---------------------------------------------------------------

  defp correr("summary", _, _, u), do: responder(Remoto.resumen(u), &texto_resumen/1)

  defp correr("simulate_conflict", [ubicacion | resto], _, u) do
    [stock, pedidos] = completar(resto, 2)

    with {:ok, stock} <- Validacion.opcional(stock, 50, &Validacion.entero_positivo(&1, :stock)),
         {:ok, pedidos} <- leer_pedidos(pedidos) do
      responder(Remoto.simular_conflicto(u, ubicacion, stock, pedidos), &texto_simulacion/1)
    else
      error -> Formato.error(error)
    end
  end

  defp correr("load_demo", _, _, u) do
    responder(Remoto.cargar_demo(u), fn
      [] -> Formato.ok("Los datos de ejemplo ya estaban cargados")
      creados -> Formato.ok("Datos de ejemplo cargados: #{Enum.join(creados, ", ")}")
    end)
  end

  defp correr(comando, _args, _opciones, _u) do
    case Map.fetch(@sintaxis, comando) do
      {:ok, sintaxis} -> Formato.error({:uso, sintaxis})
      :error -> Formato.error({:comando_desconocido, comando})
    end
  end

  # ---------------------------------------------------------------------------
  # Auxiliares de presentación
  # ---------------------------------------------------------------------------

  defp responder({:ok, valor}, formatear), do: formatear.(valor)
  defp responder(error, _formatear), do: Formato.error(error)

  # Rellena con nil los argumentos opcionales que no se escribieron.
  defp completar(lista, n), do: Enum.take(lista ++ List.duplicate(nil, n), n)

  defp leer_pedidos(nil), do: {:ok, [30, 25]}

  defp leer_pedidos(texto) do
    texto
    |> String.split(",", trim: true)
    |> Enum.reduce_while({:ok, []}, fn p, {:ok, acc} ->
      case Validacion.entero_positivo(p, :pedido) do
        {:ok, n} -> {:cont, {:ok, acc ++ [n]}}
        error -> {:halt, error}
      end
    end)
  end

  defp plan_texto(plan),
    do: Enum.map_join(plan, ", ", fn {codigo, cantidad} -> "#{cantidad} de #{codigo}" end)

  defp estado_necesidad(n), do: Formato.ok("Necesidad #{n.id}: #{Formato.etiqueta(n.estado)}")

  defp tabla_necesidades(lista) do
    Formato.tabla(
      [
        "ID",
        "PRIORIDAD",
        "TIPO",
        "CUBIERTO",
        "ZONA",
        "ESTADO",
        "ASOCIADO A",
        "RESPONSABLE",
        "DESCRIPCION"
      ],
      Enum.map(lista, fn n ->
        [
          n.id,
          n.prioridad,
          n.tipo,
          "#{n.asignada}/#{n.cantidad}",
          n.zona,
          n.estado,
          "#{n.asociado_tipo}:#{n.asociado_ref}",
          n.responsable,
          n.descripcion
        ]
      end)
    )
  end

  defp tabla_recursos(lista) do
    Formato.tabla(
      ["CODIGO", "NOMBRE", "CATEGORIA", "CANTIDAD", "UNIDAD", "UBICACION", "ZONA"],
      Enum.map(
        lista,
        &[&1.codigo, &1.nombre, &1.categoria, &1.cantidad, &1.unidad, &1.ubicacion, &1.zona]
      )
    )
  end

  defp tabla_albergues(lista) do
    Formato.tabla(
      ["CODIGO", "NOMBRE", "ZONA", "CAPACIDAD", "OCUPACION", "CUPOS", "% OCUP"],
      Enum.map(
        lista,
        &[
          &1.codigo,
          &1.nombre,
          &1.zona,
          &1.capacidad,
          &1.ocupacion,
          Albergue.cupos(&1),
          Albergue.porcentaje(&1)
        ]
      )
    )
  end

  defp tabla_personas(lista) do
    Formato.tabla(
      ["ID", "DOCUMENTO", "NOMBRE", "EDAD", "ZONA", "ESTADO", "FAMILIA"],
      Enum.map(lista, &[&1.id, &1.documento, &1.nombre, &1.edad, &1.zona, &1.estado, &1.familia])
    )
  end

  # Imprime el árbol de estadísticas recursivamente con sangría.
  defp arbol_estadisticas(nodo, profundidad) do
    t = nodo.totales
    sangria = String.duplicate("   ", profundidad)

    linea =
      "#{sangria}#{nodo.codigo} [#{nodo.tipo}#{if nodo.nivel, do: ", " <> Formato.etiqueta(nodo.nivel), else: ""}] " <>
        "afectadas: #{t.personas_afectadas} | alojadas: #{t.personas_alojadas} | albergues: #{t.albergues} | " <>
        "nec. abiertas: #{t.necesidades_abiertas} | nec. atendidas: #{t.necesidades_atendidas} | " <>
        "recursos: #{t.recursos} | personas rep.: #{t.personas_reportadas} | mascotas: #{t.mascotas_activas}"

    Enum.join([linea | Enum.map(nodo.hijos, &arbol_estadisticas(&1, profundidad + 1))], "\n")
  end

  defp texto_resumen(r) do
    recursos =
      case r.recursos_por_tipo do
        [] ->
          "ninguno"

        lista ->
          Enum.map_join(lista, ", ", fn {nombre, total, unidad} ->
            "#{nombre}: #{total} #{unidad}"
          end)
      end

    [
      Formato.titulo("RESUMEN GLOBAL DE LA EMERGENCIA"),
      "Zonas registradas: #{r.zonas}   Usuarios conectados: #{r.usuarios_conectados}",
      "Recursos restantes: #{recursos}",
      "Necesidades por estado: #{Formato.conteos(r.necesidades_por_estado)}",
      "Necesidades abiertas por prioridad: #{Formato.conteos(r.pendientes_por_prioridad)}",
      "Personas por estado: #{Formato.conteos(r.personas_por_estado)} (localizadas/ubicadas: #{r.personas_localizadas})",
      "Mensajes: #{r.mensajes_total} (pendientes de entrega: #{r.mensajes_pendientes})",
      "Mascotas por reporte: #{Formato.conteos(r.mascotas_por_tipo)}  por estado: #{Formato.conteos(r.mascotas_por_estado)}",
      "Albergues: #{r.albergues}  ocupación #{r.ocupacion_total}/#{r.capacidad_total}",
      "\nNecesidades pendientes (por prioridad):",
      tabla_necesidades(Enum.take(r.necesidades_pendientes, 10))
    ]
    |> Enum.join("\n")
  end

  defp texto_simulacion(s) do
    filas =
      Enum.map(s.resultados, fn {usuario, id, cantidad, resultado} ->
        texto =
          case resultado do
            {:ok, _} -> "CONFIRMADA"
            error -> "RECHAZADA: " <> Formato.mensaje_error(error)
          end

        [usuario, id, cantidad, texto]
      end)

    [
      Formato.titulo("Simulación de conflicto concurrente"),
      "Recurso #{s.recurso} con #{s.stock_inicial} litros; #{length(s.pedidos)} usuarios piden a la vez #{Enum.join(s.pedidos, " + ")} = #{Enum.sum(s.pedidos)} litros",
      Formato.tabla(["USUARIO", "NECESIDAD", "PIDE", "RESULTADO"], filas),
      "Total asignado: #{s.total_asignado}  Stock final: #{s.stock_final}  (nunca se asigna más que el inventario real)"
    ]
    |> Enum.join("\n")
  end

  # ---------------------------------------------------------------------------
  # Ayuda
  # ---------------------------------------------------------------------------

  defp ayuda([comando | _], _usuario) do
    case Enum.find(@ayuda, fn {c, _, s, _} -> c == comando and s != nil end) do
      {_, _, sintaxis, descripcion} -> "#{sintaxis}\n  #{descripcion}"
      nil -> Formato.error({:comando_desconocido, comando})
    end
  end

  defp ayuda([], usuario) do
    rol = usuario && usuario.tipo

    lineas =
      Enum.flat_map(@ayuda, fn
        {seccion, nil, nil, nil} ->
          ["", Formato.titulo(seccion)]

        {_c, nil, sintaxis, desc} ->
          ["  #{sintaxis}\n      #{desc}"]

        {_c, permiso, sintaxis, desc} ->
          if rol == nil or Permisos.permitido?(rol, permiso),
            do: ["  #{sintaxis}\n      #{desc}"],
            else: []
      end)

    encabezado =
      if rol,
        do: "Comandos disponibles para #{Formato.etiqueta(rol)}:",
        else: "Comandos (conéctese para ver solo los permitidos a su rol):"

    Enum.join([encabezado | lineas], "\n")
  end
end
