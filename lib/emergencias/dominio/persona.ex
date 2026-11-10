defmodule Emergencias.Dominio.Persona do
  @moduledoc """
  Persona afectada. Conserva el historial de cambios de estado como una lista de
  tuplas `{fecha, desde, hacia, usuario, detalle}` (la más reciente primero).
  """

  alias Emergencias.{Persistencia, Validacion}
  alias Emergencias.Dominio.Transiciones

  defstruct [
    :id,
    :documento,
    :nombre,
    :edad,
    :zona,
    :estado,
    :familia,
    :actualizado_en,
    historial: []
  ]

  @estados %{
    "sin_informacion" => :sin_informacion,
    "reportada" => :reportada,
    "reportado" => :reportada,
    "localizada" => :localizada,
    "localizado" => :localizada,
    "trasladada" => :trasladada,
    "trasladado" => :trasladada,
    "en_albergue" => :en_albergue,
    "albergue" => :en_albergue,
    "reunificada" => :reunificada,
    "reunificado" => :reunificada
  }

  def estados, do: Transiciones.estados(:persona)
  def validar_estado(texto), do: Validacion.opcion(texto, @estados, :estado_persona)

  def nueva(id, attrs) do
    with {:ok, documento} <- Validacion.identificador(attrs[:documento] || "", :documento),
         {:ok, nombre} <- Validacion.texto_requerido(attrs[:nombre], :nombre),
         {:ok, zona} <- Validacion.identificador(attrs[:zona] || "", :zona),
         {:ok, estado} <- Validacion.opcional(attrs[:estado], :reportada, &validar_estado/1),
         {:ok, edad} <- Validacion.opcional(attrs[:edad], nil, &validar_edad/1),
         {:ok, familia} <-
           Validacion.opcional(attrs[:familia], nil, &{:ok, Validacion.normalizar(&1)}) do
      ahora = Persistencia.ahora()

      {:ok,
       %__MODULE__{
         id: id,
         documento: documento,
         nombre: nombre,
         edad: edad,
         zona: zona,
         estado: estado,
         familia: familia,
         actualizado_en: ahora,
         historial: [{ahora, nil, estado, attrs[:usuario], "registro inicial"}]
       }}
    end
  end

  defp validar_edad(valor) do
    case Validacion.entero_no_negativo(valor, :edad) do
      {:ok, edad} when edad <= 120 -> {:ok, edad}
      {:ok, _} -> {:error, {:fuera_de_rango, :edad}}
      error -> error
    end
  end

  @doc "Cambia el estado validando la transición y agrega el cambio al historial."
  def cambiar_estado(%__MODULE__{} = persona, nuevo, usuario, detalle \\ "") do
    with :ok <- Transiciones.validar(:persona, persona.estado, nuevo) do
      ahora = Persistencia.ahora()
      cambio = {ahora, persona.estado, nuevo, usuario, detalle}

      {:ok,
       %{persona | estado: nuevo, actualizado_en: ahora, historial: [cambio | persona.historial]}}
    end
  end

  @doc "Coincidencia parcial de nombre sin importar mayúsculas ni tildes."
  def nombre_coincide?(%__MODULE__{nombre: nombre}, buscado) do
    String.contains?(Validacion.normalizar(nombre), Validacion.normalizar(buscado))
  end

  # ---------------------------------------------------------------------------
  # Persistencia (el historial va en un archivo aparte, de solo inserción)
  # ---------------------------------------------------------------------------

  def a_fila(p),
    do: [p.id, p.documento, p.nombre, p.edad, p.zona, p.estado, p.familia, p.actualizado_en]

  def desde_fila([id, documento, nombre, edad, zona, estado, familia, actualizado]) do
    %__MODULE__{
      id: id,
      documento: documento,
      nombre: nombre,
      edad: Persistencia.a_entero_o_nil(edad),
      zona: zona,
      estado: Persistencia.a_atomo(estado, estados()),
      familia: Persistencia.a_texto_o_nil(familia),
      actualizado_en: Persistencia.a_fecha(actualizado)
    }
  end

  def cambio_a_fila(documento, {fecha, desde, hacia, usuario, detalle}),
    do: [documento, fecha, desde, hacia, usuario, detalle]

  def cambio_desde_fila([documento, fecha, desde, hacia, usuario, detalle]) do
    {documento,
     {Persistencia.a_fecha(fecha), Persistencia.a_atomo(desde, estados()),
      Persistencia.a_atomo(hacia, estados()), Persistencia.a_texto_o_nil(usuario), detalle}}
  end
end
