defmodule Emergencias.Dominio.Mascota do
  @moduledoc "Reporte de mascota perdida o encontrada."

  alias Emergencias.{Persistencia, Validacion}
  alias Emergencias.Dominio.Transiciones

  defstruct [
    :id,
    :tipo_reporte,
    :especie,
    :nombre,
    :caracteristicas,
    :color,
    :tamano,
    :zona,
    :contacto,
    :estado,
    :coincidencia_con,
    :reportado_por,
    :fecha
  ]

  @tipos_reporte %{
    "lost" => :perdida,
    "perdida" => :perdida,
    "perdido" => :perdida,
    "found" => :encontrada,
    "encontrada" => :encontrada,
    "encontrado" => :encontrada
  }

  @tamanos %{
    "pequena" => :pequeno,
    "pequeno" => :pequeno,
    "small" => :pequeno,
    "mediana" => :mediano,
    "mediano" => :mediano,
    "medium" => :mediano,
    "grande" => :grande,
    "large" => :grande
  }

  @estados %{
    "activa" => :activa,
    "posible_coincidencia" => :posible_coincidencia,
    "resuelta" => :resuelta
  }

  @nombres_desconocidos ["", "desconocido", "desconocida", "sin_nombre", "?"]

  def tamanos, do: [:pequeno, :mediano, :grande]
  def estados, do: Transiciones.estados(:mascota)
  def validar_tipo_reporte(texto), do: Validacion.opcion(texto, @tipos_reporte, :tipo_reporte)
  def validar_tamano(texto), do: Validacion.opcion(texto, @tamanos, :tamano)
  def validar_estado(texto), do: Validacion.opcion(texto, @estados, :estado_mascota)

  def nueva(id, attrs) do
    with {:ok, tipo} <- validar_tipo_reporte(attrs[:tipo_reporte]),
         {:ok, especie} <- Validacion.texto_requerido(attrs[:especie], :especie),
         {:ok, color} <- Validacion.texto_requerido(attrs[:color], :color),
         {:ok, tamano} <- validar_tamano(attrs[:tamano]),
         {:ok, zona} <- Validacion.identificador(attrs[:zona] || "", :zona),
         {:ok, contacto} <- Validacion.texto_requerido(attrs[:contacto], :contacto) do
      {:ok,
       %__MODULE__{
         id: id,
         tipo_reporte: tipo,
         especie: Validacion.normalizar(especie),
         nombre: nombre_o_nil(attrs[:nombre]),
         caracteristicas: String.trim(attrs[:caracteristicas] || ""),
         color: Validacion.normalizar(color),
         tamano: tamano,
         zona: zona,
         contacto: contacto,
         estado: :activa,
         reportado_por: attrs[:usuario],
         fecha: Persistencia.ahora()
       }}
    end
  end

  defp nombre_o_nil(nombre) do
    if Validacion.normalizar(nombre) in @nombres_desconocidos, do: nil, else: String.trim(nombre)
  end

  def cambiar_estado(%__MODULE__{} = mascota, nuevo) do
    with :ok <- Transiciones.validar(:mascota, mascota.estado, nuevo) do
      {:ok, %{mascota | estado: nuevo}}
    end
  end

  def a_fila(m) do
    [
      m.id,
      m.tipo_reporte,
      m.especie,
      m.nombre,
      m.caracteristicas,
      m.color,
      m.tamano,
      m.zona,
      m.contacto,
      m.estado,
      m.coincidencia_con,
      m.reportado_por,
      m.fecha
    ]
  end

  def desde_fila([
        id,
        tipo,
        especie,
        nombre,
        caract,
        color,
        tamano,
        zona,
        contacto,
        estado,
        coinc,
        por,
        fecha
      ]) do
    %__MODULE__{
      id: id,
      tipo_reporte: Persistencia.a_atomo(tipo, [:perdida, :encontrada]),
      especie: especie,
      nombre: Persistencia.a_texto_o_nil(nombre),
      caracteristicas: caract,
      color: color,
      tamano: Persistencia.a_atomo(tamano, tamanos()),
      zona: zona,
      contacto: contacto,
      estado: Persistencia.a_atomo(estado, estados()),
      coincidencia_con: Persistencia.a_texto_o_nil(coinc),
      reportado_por: Persistencia.a_texto_o_nil(por),
      fecha: Persistencia.a_fecha(fecha)
    }
  end
end
