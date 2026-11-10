defmodule Emergencias do
  @moduledoc """
  Fachada del sistema: la ÚNICA puerta de entrada a la lógica de negocio.

  La consola (y en el futuro la interfaz web) solo llama funciones de este módulo.
  Cada operación recibe el `actor` (el `%Usuario{}` conectado), verifica sus
  permisos, valida las entradas, coordina los GenServers que correspondan y deja
  registro en la bitácora. Todas retornan `{:ok, ...}` o `{:error, motivo}`.
  """

  alias Emergencias.{Bitacora, Permisos, Validacion}
  alias Emergencias.Dominio.{Albergue, Coincidencias, Mascota, Necesidad, Persona, Recurso, Zona}

  alias Emergencias.Servidores.{
    Albergues,
    Familias,
    Inventario,
    Mascotas,
    Necesidades,
    Usuarios,
    Zonas
  }

  alias Emergencias.Sesiones.{Sesion, SupervisorSesiones}

  # ===========================================================================
  # Conexión
  # ===========================================================================

  @doc """
  `connect usuario clave [tipo] [zona] [nombre]`. Si el usuario no existe se
  registra; si existe se valida la contraseña. Abre un proceso de sesión.
  """
  def conectar(username, clave, tipo \\ nil, zona \\ nil, nombre \\ nil, cliente \\ self()) do
    with {:ok, usuario, modo} <- Usuarios.conectar(username, clave, tipo, zona, nombre),
         {:ok, sesion} <- SupervisorSesiones.abrir(usuario, cliente) do
      Bitacora.registrar(usuario.username, "connect", Atom.to_string(modo), "ok")
      {:ok, %{usuario: usuario, sesion: sesion, modo: modo}}
    else
      error ->
        Bitacora.registrar(to_string(username), "connect", inspect(error), "error")
        error
    end
  end

  def desconectar(sesion) do
    usuario = Sesion.usuario(sesion)
    Sesion.cerrar(sesion)
    Bitacora.registrar(usuario.username, "disconnect", "", "ok")
    {:ok, usuario}
  end

  def conectados, do: SupervisorSesiones.conectados()

  @doc """
  Indica si el nombre de usuario ya está registrado. Lo usa el menú para pedir
  solo la contraseña a un usuario existente y los datos completos a uno nuevo.
  """
  def usuario_registrado?(username), do: Usuarios.existe?(username)

  def listar_usuarios(actor) do
    ejecutar(actor, :list_users, "", fn ->
      conectados = MapSet.new(conectados())
      {:ok, Enum.map(Usuarios.listar(), &{&1, MapSet.member?(conectados, &1.username)})}
    end)
  end

  def cambiar_rol(actor, username, tipo) do
    ejecutar(actor, :set_role, "#{username} #{tipo}", fn ->
      with {:ok, usuario} <- Usuarios.cambiar_tipo(Validacion.normalizar(username), tipo) do
        # Si el usuario está conectado, su sesión toma el nuevo rol de inmediato.
        with {:ok, sesion} <- SupervisorSesiones.buscar(usuario.username),
             do: Sesion.actualizar_usuario(sesion, usuario)

        {:ok, usuario}
      end
    end)
  end

  @doc "Actividad propia; para ver la de otro usuario se requiere ser administrador."
  def actividad(actor, usuario \\ nil) do
    objetivo = usuario || actor.username
    accion = if objetivo == actor.username, do: :activity, else: :activity_all
    ejecutar(actor, accion, objetivo, fn -> {:ok, Bitacora.consultar(objetivo)} end, false)
  end

  # ===========================================================================
  # Zonas
  # ===========================================================================

  def registrar_zona(actor, codigo, nombre, nivel, personas \\ nil) do
    ejecutar(actor, :register_zone, "#{codigo}", fn ->
      with :ok <- codigo_libre_en_albergues(codigo),
           do: Zonas.registrar_zona(codigo, nombre, nivel, personas)
    end)
  end

  def registrar_sector(actor, zona, codigo, nombre, nivel, personas \\ nil) do
    ejecutar(actor, :register_sector, "#{zona}/#{codigo}", fn ->
      with :ok <- codigo_libre_en_albergues(codigo),
           do: Zonas.registrar_sector(zona, codigo, nombre, nivel, personas)
    end)
  end

  def registrar_punto(actor, sector, codigo, nombre, categoria \\ "atencion") do
    ejecutar(actor, :register_point, "#{sector}/#{codigo}", fn ->
      with :ok <- codigo_libre_en_albergues(codigo),
           do: Zonas.registrar_punto(sector, codigo, nombre, categoria)
    end)
  end

  @doc "Actualiza `nivel` y/o `personas` de una zona, sector o punto."
  def actualizar_zona(actor, codigo, cambios) do
    ejecutar(actor, :update_zone, "#{codigo} #{inspect(cambios)}", fn ->
      with {:ok, validados} <- validar_cambios_zona(cambios),
           do: Zonas.actualizar(codigo, validados)
    end)
  end

  defp validar_cambios_zona(cambios) do
    validar_filtros(cambios, %{
      "nivel" => fn v -> with {:ok, n} <- Zona.validar_nivel(v), do: {:ok, {:nivel, n}} end,
      "personas" => fn v ->
        with {:ok, n} <- Validacion.entero_no_negativo(v, :personas), do: {:ok, {:personas, n}}
      end
    })
  end

  def listar_zonas(actor) do
    ejecutar(actor, :list_zones, "", fn -> {:ok, Zona.aplanar(Zonas.arbol())} end, false)
  end

  @doc "Estado general de una zona: datos del nodo, ruta, albergues, necesidades y recursos."
  def estado_zona(actor, codigo) do
    ejecutar(
      actor,
      :zone_status,
      codigo,
      fn ->
        with {:ok, nodo} <- Zonas.obtener(codigo) do
          codigos = codigos_ampliados(nodo)

          {:ok,
           %{
             nodo: nodo,
             ruta: Zona.ruta(Zonas.arbol(), codigo),
             albergues: Enum.filter(Albergues.listar(), &(&1.zona in codigos)),
             necesidades_abiertas:
               Necesidades.listar(%{zonas: codigos}) |> Enum.filter(&Necesidad.abierta?/1),
             recursos:
               Enum.filter(Inventario.listar(), &(&1.zona in codigos or &1.ubicacion in codigos)),
             personas: Familias.buscar_personas(%{}) |> Enum.count(&(&1.zona in codigos)),
             mascotas_activas:
               Mascotas.listar() |> Enum.count(&(&1.zona in codigos and &1.estado != :resuelta))
           }}
        end
      end,
      false
    )
  end

  @doc """
  Estadísticas acumuladas (recursivas) de una zona y todos sus sectores y puntos.
  Primero se cuenta, por código, lo registrado directamente en cada lugar, y luego
  `Zona.acumular/2` suma recursivamente hacia arriba en el árbol.
  """
  def estadisticas_zona(actor, codigo) do
    ejecutar(
      actor,
      :zone_stats,
      codigo,
      fn ->
        with {:ok, nodo} <- Zonas.obtener(codigo) do
          {:ok, Zona.acumular(nodo, contador_por_lugar())}
        end
      end,
      false
    )
  end

  defp contador_por_lugar do
    albergues = Albergues.listar()
    zona_de_albergue = Map.new(albergues, &{&1.codigo, &1.zona})
    lugar = fn codigo -> Map.get(zona_de_albergue, codigo, codigo) end
    necesidades = Necesidades.listar()

    conteos = [
      {:necesidades_abiertas,
       necesidades |> Enum.filter(&Necesidad.abierta?/1) |> Enum.map(&lugar.(&1.zona))},
      {:necesidades_atendidas,
       necesidades |> Enum.filter(&(&1.estado == :atendida)) |> Enum.map(&lugar.(&1.zona))},
      {:recursos, Inventario.listar() |> Enum.map(&lugar.(&1.ubicacion))},
      {:albergues, Enum.map(albergues, & &1.zona)},
      {:personas_reportadas, Familias.buscar_personas(%{}) |> Enum.map(&lugar.(&1.zona))},
      {:mascotas_activas,
       Mascotas.listar() |> Enum.filter(&(&1.estado != :resuelta)) |> Enum.map(&lugar.(&1.zona))}
    ]

    tablas = Map.new(conteos, fn {clave, lugares} -> {clave, Enum.frequencies(lugares)} end)

    alojados =
      albergues
      |> Enum.group_by(& &1.zona, & &1.ocupacion)
      |> Map.new(fn {z, l} -> {z, Enum.sum(l)} end)

    fn codigo ->
      tablas
      |> Map.new(fn {clave, tabla} -> {clave, Map.get(tabla, codigo, 0)} end)
      |> Map.put(:personas_alojadas, Map.get(alojados, codigo, 0))
    end
  end

  # ===========================================================================
  # Necesidades
  # ===========================================================================

  @doc """
  Registra una necesidad. `attrs`: `tipo`, `cantidad`, `prioridad`, `zona`,
  `descripcion` y opcionalmente `asociado_a` (`persona:DOC`, `familia:X`, `albergue:A01`).
  """
  def registrar_necesidad(actor, attrs) do
    ejecutar(
      actor,
      :register_need,
      "#{attrs[:tipo]} #{attrs[:cantidad]} #{attrs[:prioridad]}",
      fn ->
        with :ok <- validar_lugar(attrs[:zona]),
             {:ok, asociado} <- Necesidad.validar_asociacion(attrs[:asociado_a], attrs[:zona]),
             :ok <- validar_asociado(asociado) do
          Necesidades.registrar(Map.put(attrs, :responsable, actor.username))
        end
      end
    )
  end

  defp validar_asociado({:albergue, codigo}), do: Albergues.obtener(codigo) |> solo_ok()

  defp validar_asociado({:persona, documento}),
    do: Familias.obtener_persona(documento) |> solo_ok()

  defp validar_asociado({:zona, codigo}), do: validar_lugar(codigo)
  defp validar_asociado({:familia, _}), do: :ok

  @doc "Filtros admitidos (texto): zona, tipo, prioridad, estado. Resultado ordenado por prioridad."
  def listar_necesidades(actor, filtros \\ %{}) do
    ejecutar(
      actor,
      :list_needs,
      inspect(filtros),
      fn ->
        with {:ok, validados} <- validar_filtros_necesidad(filtros),
             do: {:ok, Necesidades.listar(validados)}
      end,
      false
    )
  end

  @doc "Necesidades abiertas (pendiente, asignada, en atención) ordenadas por prioridad."
  def necesidades_pendientes(actor) do
    ejecutar(
      actor,
      :pending_needs,
      "",
      fn -> {:ok, Necesidades.listar() |> Enum.filter(&Necesidad.abierta?/1)} end,
      false
    )
  end

  defp validar_filtros_necesidad(filtros) do
    validar_filtros(filtros, %{
      "zona" => fn v -> with {:ok, codigos} <- codigos_lugar(v), do: {:ok, {:zonas, codigos}} end,
      "tipo" => fn v -> with {:ok, t} <- Necesidad.validar_tipo(v), do: {:ok, {:tipo, t}} end,
      "prioridad" => fn v ->
        with {:ok, p} <- Necesidad.validar_prioridad(v), do: {:ok, {:prioridad, p}}
      end,
      "estado" => fn v ->
        with {:ok, e} <- Necesidad.validar_estado(v), do: {:ok, {:estado, e}}
      end
    })
  end

  @doc "`assign_resource N001 agua 30 [desde=R001]`: retiro atómico del inventario."
  def asignar_recurso(actor, id, tipo, cantidad, opciones \\ []) do
    ejecutar(actor, :assign_resource, "#{id} #{tipo} #{cantidad}", fn ->
      with {:ok, tipo} <- Validacion.texto_requerido(tipo, :tipo),
           {:ok, necesidad, plan} <-
             Necesidades.asignar(id, tipo, cantidad, actor.username, opciones) do
        {:ok, %{necesidad: necesidad, plan: plan}}
      end
    end)
  end

  def atender_necesidad(actor, id),
    do: cambiar_estado_necesidad(actor, :attend_need, id, :en_atencion)

  def cerrar_necesidad(actor, id), do: cambiar_estado_necesidad(actor, :close_need, id, :atendida)

  def cancelar_necesidad(actor, id),
    do: cambiar_estado_necesidad(actor, :cancel_need, id, :cancelada)

  defp cambiar_estado_necesidad(actor, accion, id, estado) do
    ejecutar(actor, accion, id, fn -> Necesidades.cambiar_estado(id, estado) end)
  end

  @doc "Despacho automático por prioridad de todo el inventario disponible."
  def despachar_necesidades(actor) do
    ejecutar(actor, :dispatch_needs, "", fn -> Necesidades.despachar(actor.username) end)
  end

  # ===========================================================================
  # Recursos
  # ===========================================================================

  @doc "`attrs`: codigo, nombre, cantidad, unidad, ubicacion y opcionalmente categoria."
  def registrar_recurso(actor, attrs) do
    ejecutar(
      actor,
      :register_resource,
      "#{attrs[:codigo]} #{attrs[:nombre]} #{attrs[:cantidad]}",
      fn ->
        with {:ok, zona} <- zona_de_ubicacion(attrs[:ubicacion]) do
          Inventario.registrar(Map.put(attrs, :zona, zona), actor.username)
        end
      end
    )
  end

  def entrada_recurso(actor, codigo, cantidad, referencia \\ "") do
    ejecutar(actor, :resource_in, "#{codigo} +#{cantidad}", fn ->
      Inventario.entrada(codigo, cantidad, actor.username, referencia)
    end)
  end

  def salida_recurso(actor, codigo, cantidad, referencia \\ "") do
    ejecutar(actor, :resource_out, "#{codigo} -#{cantidad}", fn ->
      Inventario.salida(codigo, cantidad, actor.username, referencia)
    end)
  end

  @doc "Filtros admitidos: tipo (nombre o categoría), zona, ubicacion."
  def listar_recursos(actor, filtros \\ %{}) do
    ejecutar(
      actor,
      :list_resources,
      inspect(filtros),
      fn ->
        with {:ok, validados} <- validar_filtros_recurso(filtros) do
          {:ok, Enum.filter(Inventario.listar(), &recurso_cumple?(&1, validados))}
        end
      end,
      false
    )
  end

  @doc "Disponibilidad total de un tipo de recurso, opcionalmente en una zona."
  def disponibilidad(actor, tipo, zona \\ nil) do
    ejecutar(
      actor,
      :availability,
      "#{tipo} #{zona}",
      fn ->
        filtros = if zona, do: %{"tipo" => tipo, "zona" => zona}, else: %{"tipo" => tipo}

        with {:ok, validados} <- validar_filtros_recurso(filtros) do
          recursos = Enum.filter(Inventario.listar(), &recurso_cumple?(&1, validados))

          {:ok,
           %{
             tipo: tipo,
             zona: zona,
             total: recursos |> Enum.map(& &1.cantidad) |> Enum.sum(),
             recursos: recursos
           }}
        end
      end,
      false
    )
  end

  defp validar_filtros_recurso(filtros) do
    validar_filtros(filtros, %{
      "tipo" => fn v ->
        with {:ok, t} <- Validacion.texto_requerido(v, :tipo), do: {:ok, {:tipo, t}}
      end,
      "zona" => fn v -> with {:ok, codigos} <- codigos_lugar(v), do: {:ok, {:zonas, codigos}} end,
      "ubicacion" => fn v -> {:ok, {:ubicacion, v}} end
    })
  end

  defp recurso_cumple?(recurso, filtros) do
    Enum.all?(filtros, fn
      {:tipo, tipo} -> Recurso.de_tipo?(recurso, tipo)
      {:zonas, codigos} -> recurso.zona in codigos or recurso.ubicacion in codigos
      {:ubicacion, ubicacion} -> recurso.ubicacion == ubicacion
    end)
  end

  def transferir_recurso(actor, codigo, origen, destino, cantidad) do
    ejecutar(actor, :transfer_resource, "#{codigo} #{origen}->#{destino} #{cantidad}", fn ->
      with {:ok, zona_destino} <- zona_de_ubicacion(destino) do
        Inventario.transferir(codigo, origen, destino, zona_destino, cantidad, actor.username)
      end
    end)
  end

  def historial_recurso(actor, codigo \\ nil) do
    ejecutar(
      actor,
      :resource_history,
      "#{codigo}",
      fn -> {:ok, Inventario.historial(codigo)} end,
      false
    )
  end

  @doc """
  Recursos críticos: tipos cuya existencia no alcanza para la demanda abierta y
  recursos individuales por debajo del umbral configurado.
  """
  def recursos_criticos(actor) do
    ejecutar(
      actor,
      :critical_resources,
      "",
      fn ->
        umbral = Application.get_env(:emergencias, :umbral_critico, 10)
        recursos = Inventario.listar()

        demanda =
          Necesidades.listar()
          |> Enum.filter(&Necesidad.abierta?/1)
          |> Enum.group_by(&Atom.to_string(&1.tipo), &Necesidad.faltante/1)
          |> Map.new(fn {tipo, faltantes} -> {tipo, Enum.sum(faltantes)} end)
          |> Enum.filter(fn {_tipo, total} -> total > 0 end)

        por_demanda =
          demanda
          |> Enum.map(fn {tipo, requerido} ->
            disponible =
              recursos
              |> Enum.filter(&Recurso.de_tipo?(&1, tipo))
              |> Enum.map(& &1.cantidad)
              |> Enum.sum()

            %{
              tipo: tipo,
              disponible: disponible,
              demanda: requerido,
              motivo: :demanda_mayor_que_existencia
            }
          end)
          |> Enum.filter(&(&1.disponible < &1.demanda))

        por_umbral =
          for recurso <- recursos, recurso.cantidad <= umbral do
            %{recurso: recurso, umbral: umbral, motivo: :bajo_umbral}
          end

        {:ok,
         %{
           por_demanda: Enum.sort_by(por_demanda, &(&1.disponible - &1.demanda)),
           por_umbral: por_umbral
         }}
      end,
      false
    )
  end

  # ===========================================================================
  # Comunicación entre familiares
  # ===========================================================================

  @doc "`attrs`: documento, nombre, zona, estado y opcionales edad y familia."
  def reportar_persona(actor, attrs) do
    ejecutar(actor, :report_person, "#{attrs[:documento]}", fn ->
      with :ok <- validar_lugar(attrs[:zona]),
           do: Familias.registrar_persona(Map.put(attrs, :usuario, actor.username))
    end)
  end

  def actualizar_persona(actor, documento, estado, detalle \\ "") do
    ejecutar(actor, :update_person, "#{documento} #{estado}", fn ->
      with {:ok, estado} <- Persona.validar_estado(estado),
           do: Familias.cambiar_estado(documento, estado, actor.username, detalle)
    end)
  end

  def buscar_persona(actor, documento) do
    ejecutar(actor, :find_person, documento, fn -> Familias.obtener_persona(documento) end, false)
  end

  def historial_persona(actor, documento) do
    ejecutar(
      actor,
      :person_history,
      documento,
      fn ->
        with {:ok, persona} <- Familias.obtener_persona(documento), do: {:ok, persona.historial}
      end,
      false
    )
  end

  @doc "Filtros: nombre (parcial), documento, zona, estado, familia."
  def buscar_personas(actor, filtros) do
    ejecutar(
      actor,
      :search_persons,
      inspect(filtros),
      fn ->
        validadores = %{
          "nombre" => fn v -> {:ok, {:nombre, v}} end,
          "documento" => fn v -> {:ok, {:documento, v}} end,
          "zona" => fn v -> {:ok, {:zona, v}} end,
          "familia" => fn v -> {:ok, {:familia, v}} end,
          "estado" => fn v ->
            with {:ok, e} <- Persona.validar_estado(v), do: {:ok, {:estado, e}}
          end
        }

        with {:ok, validados} <- validar_filtros(filtros, validadores),
             do: {:ok, Familias.buscar_personas(validados)}
      end,
      false
    )
  end

  def enviar_mensaje(actor, destinatario, contenido) do
    ejecutar(actor, :send_family_message, destinatario, fn ->
      Familias.enviar_mensaje(actor.username, destinatario, contenido)
    end)
  end

  def mensajes_familia(actor, destinatario) do
    ejecutar(
      actor,
      :list_family_messages,
      destinatario,
      fn -> {:ok, Familias.mensajes_para(destinatario)} end,
      false
    )
  end

  def marcar_mensaje(actor, id, estado) do
    ejecutar(actor, :mark_message, "#{id} #{estado}", fn ->
      with {:ok, estado} <- Emergencias.Dominio.Mensaje.validar_estado(estado),
           do: Familias.marcar_mensaje(id, estado)
    end)
  end

  # ===========================================================================
  # Mascotas
  # ===========================================================================

  @doc "`attrs`: tipo_reporte, especie, nombre, color, tamano, zona, contacto, caracteristicas."
  def reportar_mascota(actor, attrs) do
    ejecutar(actor, :report_pet, "#{attrs[:tipo_reporte]} #{attrs[:especie]}", fn ->
      with :ok <- validar_lugar(attrs[:zona]),
           do: Mascotas.reportar(Map.put(attrs, :usuario, actor.username))
    end)
  end

  @doc "Filtros: especie, zona, estado, tipo (perdida/encontrada)."
  def listar_mascotas(actor, filtros \\ %{}) do
    ejecutar(
      actor,
      :list_pets,
      inspect(filtros),
      fn ->
        validadores = %{
          "especie" => fn v -> {:ok, {:especie, Validacion.normalizar(v)}} end,
          "zona" => fn v -> {:ok, {:zona, v}} end,
          "estado" => fn v ->
            with {:ok, e} <- Mascota.validar_estado(v), do: {:ok, {:estado, e}}
          end,
          "tipo" => fn v ->
            with {:ok, t} <- Mascota.validar_tipo_reporte(v), do: {:ok, {:tipo_reporte, t}}
          end
        }

        with {:ok, validados} <- validar_filtros(filtros, validadores),
             do: {:ok, Mascotas.listar(validados)}
      end,
      false
    )
  end

  @doc """
  Busca coincidencias entre reportes perdidos y encontrados no resueltos.
  Cada reporte perdido se compara en una tarea concurrente distinta
  (`Task.Supervisor.async_stream_nolink`); luego se marcan como
  `posible_coincidencia` los reportes involucrados.
  """
  def buscar_coincidencias(actor) do
    ejecutar(actor, :match_pets, "", fn ->
      umbral = Application.get_env(:emergencias, :umbral_coincidencia, 60)
      abiertas = Mascotas.listar() |> Enum.filter(&(&1.estado != :resuelta))
      perdidas = Enum.filter(abiertas, &(&1.tipo_reporte == :perdida))
      encontradas = Enum.filter(abiertas, &(&1.tipo_reporte == :encontrada))
      raices = Zonas.mapa_raices()

      coincidencias =
        Emergencias.Tareas
        |> Task.Supervisor.async_stream_nolink(
          perdidas,
          &Coincidencias.comparar_con_todas(&1, encontradas, umbral, raices),
          ordered: false
        )
        |> Enum.flat_map(fn
          {:ok, lista} -> lista
          {:exit, _motivo} -> []
        end)
        |> Coincidencias.ordenar()

      ids = Enum.flat_map(coincidencias, &[&1.perdida, &1.encontrada])
      {:ok, _} = Mascotas.marcar_posibles(ids)
      {:ok, coincidencias}
    end)
  end

  def confirmar_coincidencia(actor, id_a, id_b) do
    ejecutar(actor, :confirm_match, "#{id_a} #{id_b}", fn -> Mascotas.confirmar(id_a, id_b) end)
  end

  # ===========================================================================
  # Albergues
  # ===========================================================================

  @doc "`attrs`: codigo, nombre, zona, capacidad y opcional ocupacion inicial."
  def registrar_albergue(actor, attrs) do
    ejecutar(actor, :register_shelter, "#{attrs[:codigo]}", fn ->
      with :ok <- validar_lugar_arbol(attrs[:zona]),
           :ok <- codigo_libre_en_arbol(attrs[:codigo]),
           do: Albergues.registrar(attrs)
    end)
  end

  @doc "Cupos, ocupación y recursos y necesidades asociados al albergue."
  def consultar_albergue(actor, codigo) do
    ejecutar(
      actor,
      :check_shelter,
      codigo,
      fn ->
        with {:ok, albergue} <- Albergues.obtener(codigo) do
          {:ok,
           %{
             albergue: albergue,
             cupos: Albergue.cupos(albergue),
             porcentaje: Albergue.porcentaje(albergue),
             recursos: Enum.filter(Inventario.listar(), &(&1.ubicacion == codigo)),
             necesidades:
               Enum.filter(
                 Necesidades.listar(),
                 &((&1.asociado_tipo == :albergue and &1.asociado_ref == codigo) or
                     &1.zona == codigo)
               )
           }}
        end
      end,
      false
    )
  end

  @doc """
  Ingreso de una persona. Si la persona está registrada en el módulo de familiares
  su estado pasa a `en_albergue` (queda en su historial).
  """
  def registrar_ingreso(actor, codigo, documento) do
    ejecutar(actor, :register_entry, "#{codigo} #{documento}", fn ->
      with {:ok, documento} <- Validacion.identificador(documento, :documento),
           {:ok, albergue} <- Albergues.ingresar(codigo, documento) do
        nota =
          case Familias.cambiar_estado(
                 documento,
                 :en_albergue,
                 actor.username,
                 "ingreso a #{codigo}"
               ) do
            {:ok, _persona} -> :persona_actualizada
            {:error, {:no_encontrado, _}} -> :persona_no_registrada
            {:error, motivo} -> {:estado_persona_sin_cambio, motivo}
          end

        {:ok, %{albergue: albergue, nota: nota}}
      end
    end)
  end

  def registrar_salida(actor, codigo, documento) do
    ejecutar(actor, :register_exit, "#{codigo} #{documento}", fn ->
      Albergues.salir(codigo, documento)
    end)
  end

  def listar_albergues(actor) do
    ejecutar(actor, :list_shelters, "", fn -> {:ok, Albergues.listar()} end, false)
  end

  def albergues_disponibles(actor) do
    ejecutar(actor, :shelters_available, "", fn -> {:ok, Albergues.disponibles()} end, false)
  end

  def reporte_albergues(actor, n \\ 5) do
    ejecutar(
      actor,
      :shelter_report,
      "#{n}",
      fn ->
        with {:ok, n} <- Validacion.entero_positivo(n, :cantidad), do: {:ok, Albergues.ranking(n)}
      end,
      false
    )
  end

  # ===========================================================================
  # Resumen global
  # ===========================================================================

  @doc """
  Resumen global. Las siete consultas a los GenServers se lanzan EN PARALELO como
  tareas supervisadas y luego se esperan todas; el tiempo total es el de la más
  lenta y no la suma de todas.
  """
  def resumen(actor) do
    ejecutar(
      actor,
      :summary,
      "",
      fn ->
        consultas = %{
          recursos: &Inventario.listar/0,
          necesidades: fn -> Necesidades.listar() end,
          personas: fn -> Familias.buscar_personas(%{}) end,
          mensajes: &Familias.listar_mensajes/0,
          mascotas: fn -> Mascotas.listar() end,
          albergues: &Albergues.listar/0,
          zonas: &Zonas.arbol/0
        }

        datos =
          consultas
          |> Enum.map(fn {clave, consulta} ->
            {clave, Task.Supervisor.async(Emergencias.Tareas, consulta)}
          end)
          |> Map.new(fn {clave, tarea} -> {clave, Task.await(tarea)} end)

        {:ok, construir_resumen(datos)}
      end,
      false
    )
  end

  defp construir_resumen(datos) do
    abiertas = Enum.filter(datos.necesidades, &Necesidad.abierta?/1)

    %{
      zonas: length(datos.zonas),
      usuarios_conectados: length(conectados()),
      recursos_por_tipo:
        datos.recursos
        |> Enum.group_by(&{&1.nombre, &1.unidad}, & &1.cantidad)
        |> Enum.map(fn {{nombre, unidad}, cantidades} ->
          {nombre, Enum.sum(cantidades), unidad}
        end)
        |> Enum.sort(),
      necesidades_por_estado: Enum.frequencies_by(datos.necesidades, & &1.estado),
      pendientes_por_prioridad: Enum.frequencies_by(abiertas, & &1.prioridad),
      necesidades_pendientes: Necesidad.ordenar(abiertas),
      personas_por_estado: Enum.frequencies_by(datos.personas, & &1.estado),
      personas_localizadas:
        Enum.count(datos.personas, &(&1.estado != :sin_informacion and &1.estado != :reportada)),
      mensajes_total: length(datos.mensajes),
      mensajes_pendientes: Enum.count(datos.mensajes, &(&1.estado == :pendiente)),
      mascotas_por_tipo: Enum.frequencies_by(datos.mascotas, & &1.tipo_reporte),
      mascotas_por_estado: Enum.frequencies_by(datos.mascotas, & &1.estado),
      albergues: length(datos.albergues),
      capacidad_total: datos.albergues |> Enum.map(& &1.capacidad) |> Enum.sum(),
      ocupacion_total: datos.albergues |> Enum.map(& &1.ocupacion) |> Enum.sum()
    }
  end

  # ===========================================================================
  # Utilidades de demostración y pruebas
  # ===========================================================================

  def cargar_demo(actor),
    do: ejecutar(actor, :load_demo, "", fn -> Emergencias.Demo.cargar(actor) end)

  def simular_conflicto(actor, ubicacion, stock \\ 50, pedidos \\ [30, 25]) do
    ejecutar(actor, :simulate_conflict, "#{ubicacion} #{stock} #{inspect(pedidos)}", fn ->
      Emergencias.Simulacion.conflicto(actor, ubicacion, stock, pedidos)
    end)
  end

  @doc "Borra TODOS los datos (memoria y archivos). Lo usan las pruebas."
  def reiniciar_datos do
    SupervisorSesiones.cerrar_todas()

    Enum.each(
      [Usuarios, Zonas, Inventario, Necesidades, Familias, Mascotas, Albergues],
      & &1.reiniciar()
    )

    Bitacora.reiniciar()
    :ok
  end

  # ===========================================================================
  # Auxiliares
  # ===========================================================================

  # Verifica permisos, ejecuta la operación y deja constancia en la bitácora.
  # Las consultas (registrar? = false) solo se registran si fallan, para no
  # llenar la bitácora con lecturas.
  defp ejecutar(actor, accion, detalle, operacion, registrar? \\ true) do
    resultado =
      case Permisos.autorizar(actor, accion) do
        :ok -> operacion.()
        error -> error
      end

    estado = if match?({:error, _}, resultado), do: "error", else: "ok"

    if registrar? or estado == "error" do
      Bitacora.registrar(actor.username, Atom.to_string(accion), detalle, estado)
    end

    resultado
  end

  @doc false
  # Valida un mapa de filtros/cambios en texto con un validador por clave.
  def validar_filtros(filtros, validadores) do
    Enum.reduce_while(filtros, {:ok, %{}}, fn {clave, valor}, {:ok, acumulado} ->
      case Map.fetch(validadores, clave) do
        {:ok, validador} ->
          case validador.(valor) do
            {:ok, {campo, v}} -> {:cont, {:ok, Map.put(acumulado, campo, v)}}
            error -> {:halt, error}
          end

        :error ->
          {:halt, {:error, {:filtro_desconocido, clave, Map.keys(validadores)}}}
      end
    end)
  end

  # Un "lugar" válido es cualquier nodo del árbol de zonas o un albergue.
  defp validar_lugar(nil), do: {:error, {:requerido, :zona}}

  defp validar_lugar(codigo) do
    if Zonas.existe?(codigo) or Albergues.existe?(codigo),
      do: :ok,
      else: {:error, {:zona_no_registrada, codigo}}
  end

  defp validar_lugar_arbol(nil), do: {:error, {:requerido, :zona}}

  defp validar_lugar_arbol(codigo) do
    if Zonas.existe?(codigo), do: :ok, else: {:error, {:zona_no_registrada, codigo}}
  end

  defp codigo_libre_en_albergues(codigo) do
    if Albergues.existe?(codigo), do: {:error, {:id_duplicado, codigo}}, else: :ok
  end

  defp codigo_libre_en_arbol(codigo) do
    if Zonas.existe?(codigo), do: {:error, {:id_duplicado, codigo}}, else: :ok
  end

  # Códigos del subárbol más los albergues ubicados en él.
  defp codigos_ampliados(nodo) do
    codigos = Zona.codigos(nodo)
    albergues = for a <- Albergues.listar(), a.zona in codigos, do: a.codigo
    codigos ++ albergues
  end

  defp codigos_lugar(codigo) do
    case Zonas.obtener(codigo) do
      {:ok, nodo} ->
        {:ok, codigos_ampliados(nodo)}

      {:error, _} ->
        if Albergues.existe?(codigo),
          do: {:ok, [codigo]},
          else: {:error, {:zona_no_registrada, codigo}}
    end
  end

  # Zona raíz de una ubicación (punto de atención, sector, zona o albergue).
  defp zona_de_ubicacion(nil), do: {:error, {:requerido, :ubicacion}}

  defp zona_de_ubicacion(ubicacion) do
    case Zonas.raiz(ubicacion) do
      nil ->
        case Albergues.obtener(ubicacion) do
          {:ok, albergue} -> {:ok, Zonas.raiz(albergue.zona) || albergue.zona}
          {:error, _} -> {:error, {:ubicacion_no_registrada, ubicacion}}
        end

      raiz ->
        {:ok, raiz}
    end
  end

  defp solo_ok({:ok, _}), do: :ok
  defp solo_ok(error), do: error
end
