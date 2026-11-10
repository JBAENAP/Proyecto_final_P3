defmodule Emergencias.CLI.Menu do
  @moduledoc """
  Menú numerado ("ingrese 1 para..., 2 para...") sobre la consola de comandos.

  Cada opción del menú describe un comando y los datos que necesita. El menú pide
  esos datos uno por uno (los valores de catálogo, como prioridad o nivel, también
  se eligen por número), arma la línea de comando equivalente y la ejecuta con
  `CLI.Comandos.ejecutar/2`. Así el menú reutiliza toda la validación, los permisos
  y el modo distribuido sin duplicar lógica.

  Solo se muestran las opciones que el rol del usuario conectado puede usar.

  Tipos de campo:

    * `{:texto, etiqueta}`                 – obligatorio
    * `{:opcional, etiqueta, defecto}`     – Enter para omitir (se usa `defecto`)
    * `{:opcion, etiqueta, valores}`       – se elige por número
    * `{:opcion_opcional, etiqueta, valores}`
    * `{:filtro, clave, campo}`            – genera `clave=valor` si se responde
  """

  alias Emergencias.CLI.{Comandos, Formato, Remoto}
  alias Emergencias.Permisos

  @cancelar "cancelar"

  # ---------------------------------------------------------------------------
  # Catálogos (el primer elemento es el valor que entiende el comando)
  # ---------------------------------------------------------------------------

  @niveles ["critico", "alto", "medio", "bajo"]
  @prioridades ["critica", "alta", "media", "baja"]
  @tipos_necesidad ~w(agua alimentos medicamentos primeros_auxilios refugio transporte rescate otra)
  @estados_necesidad ~w(pendiente asignada en_atencion atendida cancelada)
  @estados_persona ~w(sin_informacion reportada localizada trasladada en_albergue reunificada)
  @estados_mascota ~w(activa posible_coincidencia resuelta)
  @tipos_reporte ["perdida", "encontrada"]
  @tamanos [{"pequeno", "pequeño"}, {"mediano", "mediano"}, {"grande", "grande"}]
  @tipos_usuario ["ciudadano", "voluntario", "coordinador", "administrador"]
  @categorias_punto ["acopio", "atencion", "hospital", "otro"]

  # ---------------------------------------------------------------------------
  # Definición del menú
  # ---------------------------------------------------------------------------

  defp op(texto, comando, campos \\ [], permiso \\ :del_comando),
    do: %{texto: texto, comando: comando, campos: campos, permiso: permiso}

  # Datos que se piden después del usuario: a quien ya está registrado solo su
  # contraseña; a un usuario nuevo, además, los datos de su cuenta.
  defp campos_conexion(true = _registrado), do: [{:texto, "Contraseña"}]

  defp campos_conexion(false = _registrado) do
    [
      {:texto, "Elija una contraseña (mínimo 4 caracteres)"},
      {:opcion, "Tipo de usuario", @tipos_usuario},
      {:opcional, "Zona principal", nil},
      {:opcional, "Nombre completo", nil}
    ]
  end

  @doc "Secciones del menú principal con sus opciones."
  def secciones do
    [
      {"Zonas y sectores",
       [
         op("Registrar zona", "register_zone", [
           {:texto, "Código de la zona (ej: centro)"},
           {:texto, "Nombre"},
           {:opcion, "Nivel de afectación", @niveles},
           {:opcional, "Personas afectadas estimadas", nil}
         ]),
         op("Registrar sector dentro de una zona", "register_sector", [
           {:texto, "Código de la zona"},
           {:texto, "Código del sector"},
           {:texto, "Nombre"},
           {:opcion, "Nivel de afectación", @niveles},
           {:opcional, "Personas afectadas estimadas", nil}
         ]),
         op("Registrar punto de atención / centro de acopio", "register_point", [
           {:texto, "Código del sector"},
           {:texto, "Código del punto"},
           {:texto, "Nombre"},
           {:opcion_opcional, "Categoría", @categorias_punto}
         ]),
         op("Actualizar nivel o personas afectadas", "update_zone", [
           {:texto, "Código de la zona, sector o punto"},
           {:filtro, "nivel", {:opcion_opcional, "Nuevo nivel", @niveles}},
           {:filtro, "personas", {:opcional, "Nuevas personas afectadas", nil}}
         ]),
         op("Ver árbol de zonas", "list_zones"),
         op("Estado general de una zona", "zone_status", [{:texto, "Código"}]),
         op("Estadísticas acumuladas de una zona y sus sectores", "zone_stats", [
           {:texto, "Código"}
         ])
       ]},
      {"Necesidades",
       [
         op("Registrar necesidad", "register_need", [
           {:opcion, "Tipo de necesidad", @tipos_necesidad},
           {:texto, "Cantidad requerida"},
           {:opcion, "Prioridad", @prioridades},
           {:texto, "Zona, sector, punto o albergue"},
           {:opcional, "Descripción", nil},
           {:filtro, "para",
            {:opcional, "Asociar a (albergue:A01, persona:DOC o familia:X; Enter = la zona)", nil}}
         ]),
         op("Listar necesidades (con filtros)", "list_needs", [
           {:filtro, "zona", {:opcional, "Filtrar por zona", nil}},
           {:filtro, "tipo", {:opcion_opcional, "Filtrar por tipo", @tipos_necesidad}},
           {:filtro, "prioridad", {:opcion_opcional, "Filtrar por prioridad", @prioridades}},
           {:filtro, "estado", {:opcion_opcional, "Filtrar por estado", @estados_necesidad}}
         ]),
         op("Ver necesidades pendientes (por prioridad)", "pending_needs"),
         op("Asignar recurso a una necesidad", "assign_resource", [
           {:texto, "Código de la necesidad (ej: N001)"},
           {:texto, "Tipo de recurso (ej: agua)"},
           {:texto, "Cantidad"},
           {:filtro, "desde",
            {:opcional, "Código de un recurso específico (Enter = cualquiera)", nil}}
         ]),
         op("Pasar necesidad a 'en atención'", "attend_need", [{:texto, "Código de la necesidad"}]),
         op("Marcar necesidad como atendida", "close_need", [{:texto, "Código de la necesidad"}]),
         op("Cancelar necesidad", "cancel_need", [{:texto, "Código de la necesidad"}]),
         op("Despacho automático por prioridad", "dispatch_needs")
       ]},
      {"Recursos e inventario",
       [
         op("Registrar recurso", "register_resource", [
           {:texto, "Código (ej: R001)"},
           {:texto, "Nombre o tipo (ej: agua)"},
           {:texto, "Cantidad disponible"},
           {:texto, "Unidad de medida (ej: litros)"},
           {:texto, "Ubicación (punto de atención o albergue)"},
           {:opcional, "Categoría (Enter = igual al nombre)", nil}
         ]),
         op("Ver inventario (con filtros)", "list_resources", [
           {:filtro, "tipo", {:opcional, "Filtrar por tipo", nil}},
           {:filtro, "zona", {:opcional, "Filtrar por zona", nil}},
           {:filtro, "ubicacion", {:opcional, "Filtrar por ubicación", nil}}
         ]),
         op("Registrar entrada de inventario", "resource_in", [
           {:texto, "Código del recurso"},
           {:texto, "Cantidad que entra"},
           {:opcional, "Referencia (ej: donación)", nil}
         ]),
         op("Registrar salida de inventario", "resource_out", [
           {:texto, "Código del recurso"},
           {:texto, "Cantidad que sale"},
           {:opcional, "Referencia", nil}
         ]),
         op("Consultar disponibilidad por tipo y zona", "availability", [
           {:texto, "Tipo de recurso"},
           {:opcional, "Zona (Enter = todas)", nil}
         ]),
         op("Transferir recurso entre centros", "transfer_resource", [
           {:texto, "Código del recurso"},
           {:texto, "Ubicación de origen"},
           {:texto, "Ubicación de destino"},
           {:texto, "Cantidad"}
         ]),
         op("Historial de movimientos", "resource_history", [
           {:opcional, "Código del recurso (Enter = todos)", nil}
         ]),
         op("Recursos críticos", "critical_resources")
       ]},
      {"Personas y mensajes familiares",
       [
         op("Reportar persona afectada", "report_person", [
           {:texto, "Documento"},
           {:texto, "Nombre completo"},
           {:texto, "Zona o albergue"},
           {:opcion, "Estado", @estados_persona},
           {:opcional, "Edad", nil},
           {:opcional, "Familia (apellido o grupo)", nil}
         ]),
         op("Actualizar estado de una persona", "update_person", [
           {:texto, "Documento"},
           {:opcion, "Nuevo estado", @estados_persona},
           {:opcional, "Detalle", nil}
         ]),
         op("Buscar persona por documento", "find_person", [{:texto, "Documento"}]),
         op("Buscar personas (nombre, zona, estado, familia)", "search_persons", [
           {:filtro, "nombre", {:opcional, "Nombre o parte del nombre", nil}},
           {:filtro, "zona", {:opcional, "Zona", nil}},
           {:filtro, "estado", {:opcion_opcional, "Estado", @estados_persona}},
           {:filtro, "familia", {:opcional, "Familia", nil}}
         ]),
         op("Historial de estados de una persona", "person_history", [{:texto, "Documento"}]),
         op("Enviar mensaje a una persona o familia", "send_family_message", [
           {:texto, "Destinatario (documento o familia:apellido)"},
           {:texto, "Mensaje"}
         ]),
         op("Ver mensajes de una persona o familia", "list_family_messages", [
           {:texto, "Documento o familia:apellido"}
         ]),
         op("Marcar mensaje como entregado o pendiente", "mark_message", [
           {:texto, "Código del mensaje (ej: M001)"},
           {:opcion, "Estado", ["entregado", "pendiente"]}
         ])
       ]},
      {"Mascotas perdidas y encontradas",
       [
         op("Reportar mascota", "report_pet", [
           {:opcion, "Tipo de reporte", @tipos_reporte},
           {:texto, "Especie (ej: perro)"},
           {:opcional, "Nombre (Enter = desconocido)", "desconocido"},
           {:texto, "Color"},
           {:opcion, "Tamaño", @tamanos},
           {:texto, "Zona"},
           {:texto, "Contacto"},
           {:opcional, "Características", nil}
         ]),
         op("Ver reportes (con filtros)", "list_pets", [
           {:filtro, "especie", {:opcional, "Especie", nil}},
           {:filtro, "zona", {:opcional, "Zona", nil}},
           {:filtro, "estado", {:opcion_opcional, "Estado", @estados_mascota}},
           {:filtro, "tipo", {:opcion_opcional, "Tipo de reporte", @tipos_reporte}}
         ]),
         op("Buscar posibles coincidencias", "match_pets"),
         op("Confirmar coincidencia y cerrar ambos reportes", "confirm_match", [
           {:texto, "Código del reporte de mascota perdida"},
           {:texto, "Código del reporte de mascota encontrada"}
         ])
       ]},
      {"Albergues",
       [
         op("Registrar albergue", "register_shelter", [
           {:texto, "Código (ej: A01)"},
           {:texto, "Nombre"},
           {:texto, "Zona"},
           {:texto, "Capacidad máxima"},
           {:opcional, "Ocupación actual (Enter = 0)", nil}
         ]),
         op("Consultar albergue (cupos, recursos, necesidades)", "check_shelter", [
           {:texto, "Código del albergue"}
         ]),
         op("Registrar ingreso de una persona", "register_entry", [
           {:texto, "Código del albergue"},
           {:texto, "Documento de la persona"}
         ]),
         op("Registrar salida de una persona", "register_exit", [
           {:texto, "Código del albergue"},
           {:texto, "Documento de la persona"}
         ]),
         op("Ver todos los albergues", "list_shelters"),
         op("Ver albergues con cupo", "shelters_available"),
         op("Reporte de albergues con mayor ocupación", "shelter_report", [
           {:opcional, "¿Cuántos mostrar? (Enter = 5)", nil}
         ])
       ]},
      {"Resumen y reportes",
       [
         op("Resumen global de la emergencia", "summary"),
         op("Recursos críticos", "critical_resources"),
         op("Necesidades pendientes", "pending_needs"),
         op("Reporte de ocupación de albergues", "shelter_report"),
         op("Cargar datos de ejemplo (zonas, puntos y albergues)", "load_demo"),
         op("Simular conflicto concurrente", "simulate_conflict", [
           {:texto, "Ubicación del recurso (ej: centro_acopio_1)"},
           {:opcional, "Stock inicial (Enter = 50)", nil},
           {:opcional, "Pedidos separados por coma (Enter = 30,25)", nil}
         ])
       ]},
      {"Mi cuenta y usuarios",
       [
         op("Quién soy / usuarios conectados", "whoami"),
         op("Mi actividad", "activity"),
         op("Actividad de otro usuario", "activity", [{:texto, "Usuario"}], :activity_all),
         op("Lista de usuarios", "list_users"),
         op("Cambiar el tipo de un usuario", "set_role", [
           {:texto, "Usuario"},
           {:opcion, "Nuevo tipo", @tipos_usuario}
         ])
       ]}
    ]
  end

  # ---------------------------------------------------------------------------
  # Ciclo del menú
  # ---------------------------------------------------------------------------

  @doc "Muestra el menú hasta que el usuario sale. Devuelve el estado final de la consola."
  def iniciar(estado \\ Comandos.estado_inicial()), do: bucle(estado, :principal)

  # RECURSIVA: cada vuelta muestra una pantalla, lee la opción y continúa con el
  # nuevo estado. Termina con 0 en el menú principal sin sesión o al acabarse la entrada.
  defp bucle(estado, pantalla) do
    usuario = Comandos.usuario_actual(estado)
    {titulo, opciones, salida} = pantalla(pantalla, usuario)
    mostrar(titulo, opciones, salida, usuario)

    case leer("Ingrese una opción: ") do
      :eof ->
        estado

      "0" ->
        cero(estado, pantalla, usuario)

      texto ->
        case elegir(texto, opciones) do
          nil ->
            IO.puts(Formato.error("opción no válida"))
            bucle(estado, pantalla)

          {_texto, destino} ->
            ir(estado, pantalla, destino)
        end
    end
  end

  # Qué hace el 0 en cada pantalla.
  defp cero(estado, :principal, nil), do: estado

  defp cero(estado, :principal, _usuario) do
    {nuevo, salida} = Comandos.ejecutar("disconnect", estado)
    IO.puts(salida)
    bucle(nuevo, :principal)
  end

  defp cero(estado, {:seccion, _}, _usuario), do: bucle(estado, :principal)

  defp ir(estado, _pantalla, {:seccion, _} = seccion), do: bucle(estado, seccion)
  defp ir(estado, pantalla, :comandos), do: estado |> modo_comandos() |> bucle(pantalla)
  defp ir(estado, pantalla, :conectar), do: estado |> conectar() |> bucle(pantalla)

  defp ir(estado, pantalla, {:accion, opcion}) do
    nuevo = ejecutar_opcion(estado, opcion)
    bucle(nuevo, pantalla)
  end

  # Opciones de cada pantalla según haya o no sesión y según el rol.
  defp pantalla(:principal, nil) do
    {"MENÚ PRINCIPAL",
     [
       {"Conectarse o registrarse", :conectar},
       {"Escribir un comando manualmente", :comandos}
     ], "Salir"}
  end

  defp pantalla(:principal, usuario) do
    secciones =
      secciones()
      |> Enum.with_index()
      |> Enum.filter(fn {{_nombre, opciones}, _i} -> permitidas(opciones, usuario) != [] end)
      |> Enum.map(fn {{nombre, _opciones}, i} -> {nombre, {:seccion, i}} end)

    {"MENÚ PRINCIPAL", secciones ++ [{"Escribir un comando manualmente", :comandos}],
     "Desconectarse"}
  end

  defp pantalla({:seccion, i}, usuario) do
    {nombre, opciones} = Enum.at(secciones(), i)

    {String.upcase(nombre), Enum.map(permitidas(opciones, usuario), &{&1.texto, {:accion, &1}}),
     "Volver"}
  end

  @doc "Opciones que el rol del usuario puede ejecutar."
  def permitidas(opciones, usuario) do
    Enum.filter(opciones, fn opcion ->
      case permiso(opcion) do
        nil -> true
        permiso -> Permisos.permitido?(usuario.tipo, permiso)
      end
    end)
  end

  defp permiso(%{permiso: :del_comando, comando: comando}), do: Comandos.permiso(comando)
  defp permiso(%{permiso: permiso}), do: permiso

  defp elegir(texto, opciones) do
    case Integer.parse(texto) do
      {n, ""} when n >= 1 and n <= length(opciones) -> Enum.at(opciones, n - 1)
      _ -> nil
    end
  end

  defp mostrar(titulo, opciones, salida, usuario) do
    quien =
      if usuario,
        do: "  [#{usuario.username} - #{Formato.etiqueta(usuario.tipo)}]",
        else: "  [sin conectar]"

    lineas =
      opciones
      |> Enum.with_index(1)
      |> Enum.map(fn {{texto, _destino}, n} -> "  #{n}. #{texto}" end)

    IO.puts(Enum.join(["", "== #{titulo} ==" <> quien | lineas] ++ ["  0. #{salida}", ""], "\n"))
  end

  # ---------------------------------------------------------------------------
  # Ejecución de una opción
  # ---------------------------------------------------------------------------

  defp ejecutar_opcion(estado, opcion) do
    IO.puts("\n-- #{opcion.texto} --  (escriba '#{@cancelar}' para volver)")

    case pedir_campos(opcion.campos, []) do
      :cancelado ->
        cancelado(estado)

      {:ok, valores} ->
        linea = construir_linea(opcion.comando, valores)
        # La línea equivalente ayuda a aprender los comandos.
        IO.puts("> #{linea}")
        ejecutar_linea(estado, linea)
    end
  end

  # Primero se pide el usuario y se consulta al servidor si ya existe; según eso
  # se pide solo la contraseña o los datos para crear la cuenta.
  defp conectar(estado) do
    IO.puts("\n-- Conectarse o registrarse --  (escriba '#{@cancelar}' para volver)")

    with {:arg, usuario} <- pedir({:texto, "Usuario"}),
         {:ok, registrado} <- consultar_registro(usuario),
         {:ok, valores} <- pedir_campos(campos_conexion(registrado), []) do
      # No se muestra la línea de comando: contiene la contraseña.
      ejecutar_linea(estado, construir_linea("connect", [{:arg, usuario} | valores]))
    else
      :cancelado ->
        cancelado(estado)

      {:error, motivo} ->
        IO.puts(Formato.error(motivo))
        estado
    end
  end

  defp consultar_registro(usuario) do
    case Remoto.usuario_registrado?(usuario) do
      true ->
        IO.puts("Usuario '#{usuario}' registrado. Ingrese su contraseña.")
        {:ok, true}

      false ->
        IO.puts("El usuario '#{usuario}' no existe: se creará una cuenta nueva.")
        {:ok, false}

      {:error, motivo} ->
        {:error, motivo}
    end
  end

  defp ejecutar_linea(estado, linea) do
    {nuevo, salida} = Comandos.ejecutar(linea, estado)
    IO.puts(salida)
    leer("\nPresione Enter para continuar...")
    nuevo
  end

  defp cancelado(estado) do
    IO.puts("Operación cancelada.")
    estado
  end

  # RECURSIVA: pide los campos uno a uno; caso base: no quedan campos.
  defp pedir_campos([], valores), do: {:ok, Enum.reverse(valores)}

  defp pedir_campos([campo | resto], valores) do
    case pedir(campo) do
      :cancelado -> :cancelado
      valor -> pedir_campos(resto, [valor | valores])
    end
  end

  defp pedir({:filtro, clave, campo}) do
    case pedir(campo) do
      :cancelado -> :cancelado
      {:arg, valor} -> {:opcion, clave, valor}
    end
  end

  defp pedir({:texto, etiqueta} = campo) do
    case leer("#{etiqueta}: ") do
      :eof -> :cancelado
      @cancelar -> :cancelado
      "" -> reintentar(campo, "este dato es obligatorio")
      valor -> {:arg, valor}
    end
  end

  defp pedir({:opcional, etiqueta, defecto}) do
    case leer("#{etiqueta} (Enter para omitir): ") do
      :eof -> :cancelado
      @cancelar -> :cancelado
      "" -> {:arg, defecto}
      valor -> {:arg, valor}
    end
  end

  defp pedir({tipo, etiqueta, valores} = campo) when tipo in [:opcion, :opcion_opcional] do
    IO.puts("#{etiqueta}:")

    valores
    |> Enum.with_index(1)
    |> Enum.each(fn {valor, n} -> IO.puts("    #{n}. #{etiqueta_valor(valor)}") end)

    sufijo = if tipo == :opcion_opcional, do: " (Enter para omitir)", else: ""

    case leer("  Elija 1-#{length(valores)}#{sufijo}: ") do
      :eof ->
        :cancelado

      @cancelar ->
        :cancelado

      "" when tipo == :opcion_opcional ->
        {:arg, nil}

      texto ->
        case Integer.parse(texto) do
          {n, ""} when n >= 1 and n <= length(valores) -> {:arg, valor(Enum.at(valores, n - 1))}
          _ -> reintentar(campo, "elija un número de la lista")
        end
    end
  end

  defp reintentar(campo, motivo) do
    IO.puts("  " <> motivo)
    pedir(campo)
  end

  defp valor({valor, _etiqueta}), do: valor
  defp valor(valor), do: valor

  defp etiqueta_valor({_valor, etiqueta}), do: etiqueta
  defp etiqueta_valor(valor), do: String.replace(valor, "_", " ")

  @doc """
  Arma la línea de comando a partir de las respuestas.

  `valores` es una lista de `{:arg, texto | nil}` (argumentos posicionales) y
  `{:opcion, clave, texto | nil}` (filtros `clave=valor`). Los argumentos opcionales
  omitidos al final se eliminan; si se omite uno intermedio se envía `""` para no
  correr los siguientes de posición. Los textos con espacios van entre comillas.

      iex> Emergencias.CLI.Menu.construir_linea("register_need",
      ...>   [{:arg, "agua"}, {:arg, "30"}, {:arg, "critica"}, {:arg, "centro"},
      ...>    {:arg, "Punto sector 3"}, {:opcion, "para", nil}])
      ~s(register_need agua 30 critica centro "Punto sector 3")
  """
  def construir_linea(comando, valores) do
    argumentos =
      for({:arg, valor} <- valores, do: valor)
      |> Enum.reverse()
      |> Enum.drop_while(&is_nil/1)
      |> Enum.reverse()
      |> Enum.map(&citar(&1 || ""))

    opciones =
      for {:opcion, clave, valor} <- valores, valor != nil, do: "#{clave}=#{citar(valor)}"

    Enum.join([comando | argumentos ++ opciones], " ")
  end

  defp citar(texto) do
    texto = String.replace(texto, "\"", "'")
    if texto == "" or String.match?(texto, ~r/[\s=]/u), do: ~s("#{texto}"), else: texto
  end

  # ---------------------------------------------------------------------------
  # Modo de comandos escritos (para quien prefiera escribir)
  # ---------------------------------------------------------------------------

  # RECURSIVA: ejecuta comandos escritos hasta que el usuario escribe 'menu'.
  defp modo_comandos(estado) do
    IO.puts("\nModo comandos: escriba 'help' para ver los comandos y 'menu' para volver.")
    modo_comandos_bucle(estado)
  end

  defp modo_comandos_bucle(estado) do
    case leer("comando> ") do
      :eof ->
        estado

      texto when texto in ["menu", "menú", "volver"] ->
        estado

      linea ->
        {nuevo, salida} = Comandos.ejecutar(linea, estado)
        if salida != "", do: IO.puts(salida)
        modo_comandos_bucle(nuevo)
    end
  end

  defp leer(mensaje) do
    case IO.gets(mensaje) do
      :eof -> :eof
      {:error, _} -> :eof
      texto -> String.trim(texto)
    end
  end
end
