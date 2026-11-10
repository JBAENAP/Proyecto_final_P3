defmodule Emergencias.Servidores.Familias do
  @moduledoc """
  GenServer para la comunicación entre familiares: personas afectadas
  (`%{documento => %Persona{}}`) y mensajes (`%{id => %Mensaje{}}`).
  El historial de cambios de estado de cada persona se guarda aparte, en un
  archivo de solo inserción.
  """

  use GenServer

  alias Emergencias.{Persistencia, Validacion}
  alias Emergencias.Dominio.{Mensaje, Persona}

  @archivo_personas "personas.txt"
  @archivo_historial "historial_personas.txt"
  @archivo_mensajes "mensajes.txt"

  # ---------------------------------------------------------------------------
  # API
  # ---------------------------------------------------------------------------

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  def registrar_persona(attrs), do: GenServer.call(__MODULE__, {:registrar_persona, attrs})
  def obtener_persona(documento), do: GenServer.call(__MODULE__, {:obtener_persona, documento})

  def cambiar_estado(documento, estado, usuario, detalle \\ ""),
    do: GenServer.call(__MODULE__, {:cambiar_estado, documento, estado, usuario, detalle})

  @doc "Filtros admitidos: `:nombre` (parcial), `:documento`, `:zona`, `:estado`, `:familia`."
  def buscar_personas(filtros), do: GenServer.call(__MODULE__, {:buscar_personas, filtros})

  def enviar_mensaje(remitente, destinatario, contenido),
    do: GenServer.call(__MODULE__, {:enviar_mensaje, remitente, destinatario, contenido})

  @doc "Mensajes dirigidos a la persona o a su familia."
  def mensajes_para(destinatario), do: GenServer.call(__MODULE__, {:mensajes_para, destinatario})

  def marcar_mensaje(id, estado),
    do: GenServer.call(__MODULE__, {:marcar_mensaje, String.upcase(id), estado})

  def listar_mensajes, do: GenServer.call(__MODULE__, :listar_mensajes)
  def reiniciar, do: GenServer.call(__MODULE__, :reiniciar)

  # ---------------------------------------------------------------------------
  # Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(:ok) do
    historiales =
      @archivo_historial
      |> Persistencia.leer()
      |> Enum.map(&Persona.cambio_desde_fila/1)
      |> Enum.group_by(fn {documento, _} -> documento end, fn {_, cambio} -> cambio end)

    personas =
      @archivo_personas
      |> Persistencia.leer()
      |> Map.new(fn fila ->
        persona = Persona.desde_fila(fila)
        historial = historiales |> Map.get(persona.documento, []) |> Enum.reverse()
        {persona.documento, %{persona | historial: historial}}
      end)

    mensajes =
      @archivo_mensajes
      |> Persistencia.leer()
      |> Map.new(fn fila ->
        mensaje = Mensaje.desde_fila(fila)
        {mensaje.id, mensaje}
      end)

    {:ok,
     %{
       personas: personas,
       mensajes: mensajes,
       siguiente_persona: siguiente(Map.values(personas), "P"),
       siguiente_mensaje: siguiente(Map.values(mensajes), "M")
     }}
  end

  @impl true
  def handle_call({:registrar_persona, attrs}, _de, estado) do
    id = formatear_id("P", estado.siguiente_persona)

    with {:ok, persona} <- Persona.nueva(id, attrs),
         :ok <- no_duplicada(estado, persona.documento) do
      [cambio] = persona.historial
      Persistencia.agregar(@archivo_historial, Persona.cambio_a_fila(persona.documento, cambio))

      nuevo =
        %{estado | siguiente_persona: estado.siguiente_persona + 1} |> poner_persona(persona)

      {:reply, {:ok, persona}, nuevo}
    else
      error -> {:reply, error, estado}
    end
  end

  def handle_call({:obtener_persona, documento}, _de, estado),
    do: {:reply, buscar_persona(estado, documento), estado}

  def handle_call({:cambiar_estado, documento, nuevo_estado, usuario, detalle}, _de, estado) do
    with {:ok, persona} <- buscar_persona(estado, documento),
         {:ok, actualizada} <- Persona.cambiar_estado(persona, nuevo_estado, usuario, detalle) do
      [cambio | _] = actualizada.historial
      Persistencia.agregar(@archivo_historial, Persona.cambio_a_fila(documento, cambio))
      {:reply, {:ok, actualizada}, poner_persona(estado, actualizada)}
    else
      error -> {:reply, error, estado}
    end
  end

  def handle_call({:buscar_personas, filtros}, _de, estado) do
    resultado =
      estado.personas
      |> Map.values()
      |> Enum.filter(fn persona ->
        Enum.all?(filtros, fn
          {:nombre, nombre} -> Persona.nombre_coincide?(persona, nombre)
          {:familia, familia} -> persona.familia == Validacion.normalizar(familia)
          {campo, valor} -> Map.get(persona, campo) == valor
        end)
      end)
      |> Enum.sort_by(& &1.nombre)

    {:reply, resultado, estado}
  end

  def handle_call({:enviar_mensaje, remitente, destinatario, contenido}, _de, estado) do
    id = formatear_id("M", estado.siguiente_mensaje)

    with :ok <- destinatario_existe(estado, Mensaje.tipo_destinatario(destinatario)),
         {:ok, mensaje} <-
           Mensaje.nuevo(id, remitente, normalizar_destinatario(destinatario), contenido) do
      nuevo =
        %{estado | siguiente_mensaje: estado.siguiente_mensaje + 1} |> poner_mensaje(mensaje)

      {:reply, {:ok, mensaje}, nuevo}
    else
      error -> {:reply, error, estado}
    end
  end

  def handle_call({:mensajes_para, destinatario}, _de, estado) do
    destinos =
      case Mensaje.tipo_destinatario(destinatario) do
        {:familia, familia} ->
          ["familia:" <> familia]

        {:persona, documento} ->
          case Map.fetch(estado.personas, documento) do
            {:ok, %Persona{familia: nil}} -> [documento]
            {:ok, %Persona{familia: familia}} -> [documento, "familia:" <> familia]
            :error -> [documento]
          end
      end

    mensajes =
      estado.mensajes
      |> Map.values()
      |> Enum.filter(&(&1.destinatario in destinos))
      |> Enum.sort_by(& &1.id)

    {:reply, mensajes, estado}
  end

  def handle_call({:marcar_mensaje, id, nuevo_estado}, _de, estado) do
    with {:ok, mensaje} <- Map.fetch(estado.mensajes, id) |> encontrado(id),
         {:ok, actualizado} <- Mensaje.cambiar_estado(mensaje, nuevo_estado) do
      {:reply, {:ok, actualizado}, poner_mensaje(estado, actualizado)}
    else
      error -> {:reply, error, estado}
    end
  end

  def handle_call(:listar_mensajes, _de, estado),
    do: {:reply, estado.mensajes |> Map.values() |> Enum.sort_by(& &1.id), estado}

  def handle_call(:reiniciar, _de, _estado) do
    Enum.each(
      [@archivo_personas, @archivo_historial, @archivo_mensajes],
      &Persistencia.eliminar/1
    )

    {:reply, :ok, %{personas: %{}, mensajes: %{}, siguiente_persona: 1, siguiente_mensaje: 1}}
  end

  # ---------------------------------------------------------------------------
  # Auxiliares
  # ---------------------------------------------------------------------------

  defp buscar_persona(estado, documento),
    do: Map.fetch(estado.personas, documento) |> encontrado(documento)

  defp encontrado({:ok, valor}, _id), do: {:ok, valor}
  defp encontrado(:error, id), do: {:error, {:no_encontrado, id}}

  defp no_duplicada(estado, documento) do
    if Map.has_key?(estado.personas, documento),
      do: {:error, {:id_duplicado, documento}},
      else: :ok
  end

  defp destinatario_existe(estado, {:persona, documento}) do
    if Map.has_key?(estado.personas, documento),
      do: :ok,
      else: {:error, {:no_encontrado, documento}}
  end

  defp destinatario_existe(estado, {:familia, familia}) do
    if Enum.any?(Map.values(estado.personas), &(&1.familia == familia)),
      do: :ok,
      else: {:error, {:no_encontrado, "familia:" <> familia}}
  end

  defp normalizar_destinatario(destinatario) do
    case Mensaje.tipo_destinatario(destinatario) do
      {:familia, familia} -> "familia:" <> familia
      {:persona, documento} -> documento
    end
  end

  defp poner_persona(estado, persona) do
    personas = Map.put(estado.personas, persona.documento, persona)

    Persistencia.guardar(
      @archivo_personas,
      personas |> Map.values() |> Enum.map(&Persona.a_fila/1)
    )

    %{estado | personas: personas}
  end

  defp poner_mensaje(estado, mensaje) do
    mensajes = Map.put(estado.mensajes, mensaje.id, mensaje)

    Persistencia.guardar(
      @archivo_mensajes,
      mensajes |> Map.values() |> Enum.map(&Mensaje.a_fila/1)
    )

    %{estado | mensajes: mensajes}
  end

  defp formatear_id(prefijo, numero),
    do: prefijo <> String.pad_leading(Integer.to_string(numero), 3, "0")

  defp siguiente(registros, prefijo) do
    registros
    |> Enum.map(fn %{id: id} ->
      id |> String.replace_prefix(prefijo, "") |> String.to_integer()
    end)
    |> Enum.max(fn -> 0 end)
    |> Kernel.+(1)
  end
end
