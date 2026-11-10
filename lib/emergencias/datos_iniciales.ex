defmodule Emergencias.DatosIniciales do
  @moduledoc """
  Datos de muestra ("quemados") ambientados en Armenia, Quindío.

  Las zonas son las 10 comunas oficiales de Armenia más el corregimiento El Caimo.
  Los sectores, puntos de atención, albergues, recursos, personas, necesidades,
  mensajes y mascotas son FICTICIOS: solo sirven para probar el sistema.

  Crea además un usuario por cada tipo, todos con la contraseña `0000`:

  | Usuario | Tipo          |
  |---------|---------------|
  | pedro   | ciudadano     |
  | andres  | voluntario    |
  | laura   | coordinador   |
  | sofia   | administrador |

  Todo se registra a través de la fachada `Emergencias`, con el usuario del rol
  que corresponde, así que pasa por las mismas validaciones y queda en la bitácora.
  Se carga automáticamente al iniciar el servidor si todavía no hay zonas.
  """

  alias Emergencias.Servidores.{Usuarios, Zonas}

  @clave "0000"

  @usuarios [
    {"pedro", "ciudadano", "comuna_3", "Pedro Ramírez"},
    {"andres", "voluntario", "comuna_5", "Andrés Gómez"},
    {"laura", "coordinador", "comuna_1", "Laura Gómez"},
    {"sofia", "administrador", "comuna_9", "Sofía Martínez"}
  ]

  # {código, nombre, nivel, personas afectadas fuera de los sectores}
  @zonas [
    {"comuna_1", "Comuna 1 - Centenario", "alto", 150},
    {"comuna_2", "Comuna 2 - Rufino José Cuervo", "medio", 100},
    {"comuna_3", "Comuna 3 - Alfonso López", "critico", 220},
    {"comuna_4", "Comuna 4 - Francisco de Paula Santander", "alto", 180},
    {"comuna_5", "Comuna 5 - El Bosque", "critico", 250},
    {"comuna_6", "Comuna 6 - San José", "medio", 90},
    {"comuna_7", "Comuna 7 - Cafetero", "alto", 160},
    {"comuna_8", "Comuna 8 - Libertadores", "medio", 80},
    {"comuna_9", "Comuna 9 - Fundadores", "bajo", 40},
    {"comuna_10", "Comuna 10 - Quimbaya", "bajo", 60},
    {"el_caimo", "Corregimiento El Caimo", "alto", 30}
  ]

  # Cada comuna tiene un sector norte y uno sur: {zona, código, nombre, nivel, personas}
  @sectores (for {zona, nombre, nivel, personas} <- [
                   {"comuna_1", "Centenario", ["alto", "medio"], [1300, 950]},
                   {"comuna_2", "Rufino J. Cuervo", ["medio", "bajo"], [900, 800]},
                   {"comuna_3", "Alfonso López", ["critico", "alto"], [1700, 1200]},
                   {"comuna_4", "Fco. de Paula Santander", ["alto", "alto"], [1400, 1100]},
                   {"comuna_5", "El Bosque", ["critico", "critico"], [1800, 1350]},
                   {"comuna_6", "San José", ["medio", "medio"], [750, 660]},
                   {"comuna_7", "Cafetero", ["alto", "medio"], [1200, 840]},
                   {"comuna_8", "Libertadores", ["medio", "bajo"], [700, 520]},
                   {"comuna_9", "Fundadores", ["bajo", "bajo"], [480, 380]},
                   {"comuna_10", "Quimbaya", ["bajo", "medio"], [500, 540]}
                 ],
                 {lado, nivel_sector, personas_sector} <-
                   Enum.zip([["norte", "sur"], nivel, personas]) do
               {zona, "#{zona}_#{lado}", "#{nombre} #{String.capitalize(lado)}", nivel_sector,
                personas_sector}
             end) ++
              [
                {"el_caimo", "caimo_centro", "Centro poblado El Caimo", "alto", 420},
                {"el_caimo", "caimo_veredas", "Veredas La India y Puerto Espejo", "medio", 200}
              ]

  # {sector, código, nombre, categoría}
  @puntos [
    {"comuna_1_norte", "acopio_c1", "Centro de acopio Comuna 1", "acopio"},
    {"comuna_1_sur", "salud_c1", "Puesto de salud Comuna 1", "salud"},
    {"comuna_2_norte", "acopio_c2", "Centro de acopio Comuna 2", "acopio"},
    {"comuna_3_norte", "acopio_c3", "Centro de acopio Comuna 3", "acopio"},
    {"comuna_3_sur", "atencion_c3", "Punto de atención Comuna 3", "atencion"},
    {"comuna_4_norte", "acopio_c4", "Centro de acopio Comuna 4", "acopio"},
    {"comuna_5_norte", "acopio_c5", "Centro de acopio Comuna 5", "acopio"},
    {"comuna_5_sur", "salud_c5", "Puesto de salud Comuna 5", "salud"},
    {"comuna_6_norte", "atencion_c6", "Punto de atención Comuna 6", "atencion"},
    {"comuna_7_norte", "acopio_c7", "Centro de acopio Comuna 7", "acopio"},
    {"comuna_8_sur", "atencion_c8", "Punto de atención Comuna 8", "atencion"},
    {"comuna_9_norte", "acopio_c9", "Centro de acopio Comuna 9", "acopio"},
    {"comuna_10_sur", "atencion_c10", "Punto de atención Comuna 10", "atencion"},
    {"caimo_centro", "acopio_caimo", "Centro de acopio El Caimo", "acopio"}
  ]

  @albergues [
    %{
      codigo: "AL01",
      nombre: "Albergue Comuna 3",
      zona: "comuna_3",
      capacidad: 200,
      ocupacion: 142
    },
    %{
      codigo: "AL02",
      nombre: "Albergue Comuna 5",
      zona: "comuna_5",
      capacidad: 250,
      ocupacion: 231
    },
    %{
      codigo: "AL03",
      nombre: "Albergue Comuna 1",
      zona: "comuna_1",
      capacidad: 120,
      ocupacion: 64
    },
    %{
      codigo: "AL04",
      nombre: "Albergue Comuna 7",
      zona: "comuna_7",
      capacidad: 150,
      ocupacion: 150
    },
    %{codigo: "AL05", nombre: "Albergue El Caimo", zona: "el_caimo", capacidad: 60, ocupacion: 18}
  ]

  # {código, nombre, cantidad, unidad, ubicación, categoría}
  @recursos [
    {"R001", "agua", 2000, "litros", "acopio_c1", "agua"},
    {"R002", "agua", 1500, "litros", "acopio_c5", "agua"},
    {"R003", "agua", 400, "litros", "AL02", "agua"},
    {"R004", "mercados", 800, "raciones", "acopio_c3", "alimentos"},
    {"R005", "mercados", 8, "raciones", "acopio_caimo", "alimentos"},
    {"R006", "analgesicos", 300, "cajas", "acopio_c4", "medicamentos"},
    {"R007", "antibioticos", 6, "cajas", "salud_c5", "medicamentos"},
    {"R008", "botiquines", 120, "unidades", "acopio_c7", "primeros_auxilios"},
    {"R009", "cobijas", 500, "unidades", "AL01", "refugio"},
    {"R010", "carpas", 60, "unidades", "acopio_c9", "refugio"},
    {"R011", "colchonetas", 200, "unidades", "AL02", "refugio"},
    {"R012", "kits de higiene", 5, "kits", "acopio_c2", "higiene"},
    {"R013", "linternas", 90, "unidades", "acopio_c7", "herramientas"}
  ]

  # {documento, nombre, zona, estado, edad, familia}
  @personas [
    {"1094001001", "María Fernanda Osorio", "comuna_3", "localizada", "34", "osorio"},
    {"1094001002", "Juan David Osorio", "comuna_3", "sin_informacion", "9", "osorio"},
    {"1094002001", "Carlos Arturo Giraldo", "comuna_5", "reportada", "67", "giraldo"},
    {"1094002002", "Luz Marina Giraldo", "comuna_5", "localizada", "63", "giraldo"},
    {"1094003001", "Andrés Felipe Restrepo", "comuna_1", "trasladada", "45", "restrepo"},
    {"1094004001", "Paula Andrea Cardona", "el_caimo", "localizada", "28", "cardona"},
    {"1094005001", "Jorge Iván Henao", "comuna_7", "reportada", "52", "henao"},
    {"1094005002", "Valentina Henao", "comuna_7", "reunificada", "17", "henao"}
  ]

  # Personas que entran a un albergue: {albergue, documento}
  @ingresos [{"AL01", "1094001001"}, {"AL02", "1094002002"}]

  # {usuario que la registra, atributos, acciones posteriores del coordinador}
  @necesidades [
    {"pedro",
     %{
       tipo: "agua",
       cantidad: 300,
       prioridad: "critica",
       zona: "comuna_3_norte",
       descripcion: "Barrio sin servicio de acueducto"
     }, [{:asignar, "agua", 200}]},
    {"andres",
     %{
       tipo: "medicamentos",
       cantidad: 40,
       prioridad: "critica",
       zona: "comuna_5",
       descripcion: "Adultos mayores con enfermedades crónicas",
       asociado_a: "albergue:AL02"
     }, []},
    {"laura",
     %{
       tipo: "rescate",
       cantidad: 1,
       prioridad: "critica",
       zona: "comuna_7_norte",
       descripcion: "Posibles personas atrapadas en edificio colapsado"
     }, []},
    {"andres",
     %{
       tipo: "alimentos",
       cantidad: 150,
       prioridad: "alta",
       zona: "AL02",
       descripcion: "Raciones para tres días",
       asociado_a: "albergue:AL02"
     }, []},
    {"pedro",
     %{
       tipo: "refugio",
       cantidad: 80,
       prioridad: "alta",
       zona: "comuna_4",
       descripcion: "Familias con viviendas colapsadas"
     }, []},
    {"laura",
     %{
       tipo: "primeros_auxilios",
       cantidad: 25,
       prioridad: "alta",
       zona: "salud_c1",
       descripcion: "Heridos leves en el sector Centenario"
     }, [{:asignar, "primeros_auxilios", 25}, :atender, :cerrar]},
    {"pedro",
     %{
       tipo: "alimentos",
       cantidad: 60,
       prioridad: "media",
       zona: "comuna_3_sur",
       descripcion: "Familia Osorio",
       asociado_a: "familia:osorio"
     }, []},
    {"laura",
     %{
       tipo: "transporte",
       cantidad: 3,
       prioridad: "media",
       zona: "el_caimo",
       descripcion: "Traslado de heridos desde las veredas"
     }, []},
    {"andres",
     %{
       tipo: "agua",
       cantidad: 50,
       prioridad: "baja",
       zona: "comuna_9",
       descripcion: "Reserva para el punto de atención"
     }, [:cancelar]}
  ]

  # {remitente, destinatario, contenido, ¿entregado?}
  @mensajes [
    {"pedro", "1094001002", "Juanito, tu mamá está en el Albergue Comuna 3. Te estamos buscando.",
     false},
    {"andres", "familia:giraldo", "Luz Marina está bien, quedó en el Albergue Comuna 5.", true},
    {"pedro", "1094002001", "Don Carlos, comuníquese con su familia en el Albergue Comuna 5.",
     false},
    {"laura", "familia:henao", "Valentina ya está con sus tíos en la Comuna 7.", true}
  ]

  # {usuario, atributos}
  @mascotas [
    {"pedro",
     %{
       tipo_reporte: "lost",
       especie: "perro",
       nombre: "Max",
       color: "cafe",
       tamano: "grande",
       zona: "comuna_3",
       contacto: "3101234567",
       caracteristicas: "collar rojo, cojea de la pata trasera"
     }},
    {"andres",
     %{
       tipo_reporte: "found",
       especie: "perro",
       nombre: "",
       color: "cafe oscuro",
       tamano: "grande",
       zona: "comuna_3_sur",
       contacto: "3157654321",
       caracteristicas: "collar rojo, cojea"
     }},
    {"pedro",
     %{
       tipo_reporte: "lost",
       especie: "gato",
       nombre: "Misu",
       color: "blanco",
       tamano: "pequeno",
       zona: "comuna_5",
       contacto: "3209876543",
       caracteristicas: "ojos azules, muy asustadizo"
     }},
    {"andres",
     %{
       tipo_reporte: "found",
       especie: "gato",
       nombre: "",
       color: "blanco y gris",
       tamano: "pequeno",
       zona: "comuna_4",
       contacto: "3112223344",
       caracteristicas: "ojos azules"
     }},
    {"laura",
     %{
       tipo_reporte: "lost",
       especie: "perro",
       nombre: "Rocky",
       color: "negro",
       tamano: "mediano",
       zona: "el_caimo",
       contacto: "3005556677",
       caracteristicas: "sin collar, mancha blanca en el pecho"
     }}
  ]

  @doc "Lista `{usuario, tipo}` de los usuarios de muestra (todos con clave `0000`)."
  def usuarios, do: Enum.map(@usuarios, fn {u, tipo, _zona, _nombre} -> {u, tipo} end)

  @doc """
  Carga los datos solo si todavía no hay zonas registradas, para no duplicar
  personas, necesidades o mensajes cada vez que se inicia el servidor.
  """
  def cargar_si_vacio do
    if Zonas.arbol() == [], do: cargar(), else: {:ok, :ya_habia_datos}
  end

  @doc """
  Lo llaman `mix servidor` y `mix consola` al arrancar: carga los datos si hace
  falta e informa qué pasó.
  """
  def cargar_al_iniciar do
    case cargar_si_vacio() do
      {:ok, :ya_habia_datos} ->
        :ok

      {:ok, %{creados: creados, errores: errores}} ->
        # La bitácora es asíncrona: una consulta asegura que ya procesó todo lo anterior.
        Emergencias.Bitacora.consultar(nil, 1)

        IO.puts(
          "Datos de muestra de Armenia cargados (#{creados} registros). " <>
            "Usuarios: " <>
            Enum.map_join(usuarios(), ", ", fn {u, tipo} -> "#{u} (#{tipo})" end) <>
            " - contraseña de todos: #{@clave}"
        )

        Enum.each(errores, fn {dato, motivo} ->
          IO.puts("  No se pudo cargar #{dato}: #{Emergencias.CLI.Formato.error(motivo)}")
        end)
    end
  end

  @doc """
  Registra todos los datos de muestra. Devuelve `{:ok, %{creados: n, errores: lista}}`;
  un dato que falla (por ejemplo, un código que ya existe) se reporta y se sigue con el resto.
  """
  def cargar do
    actores = crear_usuarios()
    actor = &Map.fetch!(actores, &1)
    coordinador = actor.("laura")
    voluntario = actor.("andres")

    resultados =
      Enum.map(@zonas, fn {codigo, nombre, nivel, personas} ->
        {codigo, Emergencias.registrar_zona(coordinador, codigo, nombre, nivel, personas)}
      end) ++
        Enum.map(@sectores, fn {zona, codigo, nombre, nivel, personas} ->
          {codigo,
           Emergencias.registrar_sector(coordinador, zona, codigo, nombre, nivel, personas)}
        end) ++
        Enum.map(@puntos, fn {sector, codigo, nombre, categoria} ->
          {codigo, Emergencias.registrar_punto(coordinador, sector, codigo, nombre, categoria)}
        end) ++
        Enum.map(@albergues, &{&1.codigo, Emergencias.registrar_albergue(coordinador, &1)}) ++
        Enum.map(@recursos, fn {codigo, nombre, cantidad, unidad, ubicacion, categoria} ->
          attrs = %{
            codigo: codigo,
            nombre: nombre,
            cantidad: cantidad,
            unidad: unidad,
            ubicacion: ubicacion,
            categoria: categoria
          }

          {codigo, Emergencias.registrar_recurso(coordinador, attrs)}
        end) ++
        Enum.map(@personas, fn {documento, nombre, zona, estado, edad, familia} ->
          attrs = %{
            documento: documento,
            nombre: nombre,
            zona: zona,
            estado: estado,
            edad: edad,
            familia: familia
          }

          {documento, Emergencias.reportar_persona(voluntario, attrs)}
        end) ++
        Enum.map(@ingresos, fn {albergue, documento} ->
          {"#{albergue}/#{documento}",
           Emergencias.registrar_ingreso(voluntario, albergue, documento)}
        end) ++
        Enum.flat_map(@necesidades, fn {usuario, attrs, acciones} ->
          registrar_necesidad(actor.(usuario), coordinador, attrs, acciones)
        end) ++
        Enum.flat_map(@mensajes, fn {usuario, destinatario, contenido, entregado?} ->
          enviar_mensaje(actor.(usuario), voluntario, destinatario, contenido, entregado?)
        end) ++
        Enum.map(@mascotas, fn {usuario, attrs} ->
          {"mascota #{attrs.especie}", Emergencias.reportar_mascota(actor.(usuario), attrs)}
        end)

    errores = for {dato, {:error, motivo}} <- resultados, do: {dato, motivo}

    {:ok,
     %{
       usuarios: map_size(actores),
       creados: length(resultados) - length(errores),
       errores: errores
     }}
  end

  # Registra cada usuario con la clave 0000 (si ya existe se deja como está)
  # y devuelve %{username => %Usuario{}} para actuar en su nombre.
  defp crear_usuarios do
    Map.new(@usuarios, fn {username, tipo, zona, nombre} ->
      Usuarios.conectar(username, @clave, tipo, zona, nombre)
      {:ok, usuario} = Usuarios.obtener(username)
      {username, usuario}
    end)
  end

  defp registrar_necesidad(actor, coordinador, attrs, acciones) do
    case Emergencias.registrar_necesidad(actor, attrs) do
      {:ok, necesidad} ->
        [
          {necesidad.id, {:ok, necesidad}}
          | Enum.map(
              acciones,
              &{"#{necesidad.id} #{inspect(&1)}", accion(coordinador, necesidad.id, &1)}
            )
        ]

      error ->
        [{"necesidad #{attrs.tipo}", error}]
    end
  end

  defp accion(actor, id, {:asignar, tipo, cantidad}),
    do: Emergencias.asignar_recurso(actor, id, tipo, cantidad)

  defp accion(actor, id, :atender), do: Emergencias.atender_necesidad(actor, id)
  defp accion(actor, id, :cerrar), do: Emergencias.cerrar_necesidad(actor, id)
  defp accion(actor, id, :cancelar), do: Emergencias.cancelar_necesidad(actor, id)

  defp enviar_mensaje(actor, voluntario, destinatario, contenido, entregado?) do
    case Emergencias.enviar_mensaje(actor, destinatario, contenido) do
      {:ok, mensaje} when entregado? ->
        [
          {mensaje.id, {:ok, mensaje}},
          {"#{mensaje.id} entregado",
           Emergencias.marcar_mensaje(voluntario, mensaje.id, "entregado")}
        ]

      resultado ->
        [{"mensaje a #{destinatario}", resultado}]
    end
  end
end
