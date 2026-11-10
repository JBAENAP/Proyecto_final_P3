defmodule Emergencias.Dominio.Mensaje do
  @moduledoc """
  Mensaje para familiares. El destinatario es el documento de una persona
  o `familia:<nombre>` para un grupo familiar.
  """

  alias Emergencias.{Persistencia, Validacion}
  alias Emergencias.Dominio.Transiciones

  defstruct [:id, :fecha, :remitente, :destinatario, :contenido, :estado]

  @estados %{
    "pendiente" => :pendiente,
    "entregado" => :entregado,
    "entregada" => :entregado
  }

  def validar_estado(texto), do: Validacion.opcion(texto, @estados, :estado_mensaje)

  def nuevo(id, remitente, destinatario, contenido) do
    with {:ok, contenido} <- Validacion.texto_requerido(contenido, :contenido),
         {:ok, destinatario} <- Validacion.texto_requerido(destinatario, :destinatario) do
      {:ok,
       %__MODULE__{
         id: id,
         fecha: Persistencia.ahora(),
         remitente: remitente,
         destinatario: destinatario,
         contenido: contenido,
         estado: :pendiente
       }}
    end
  end

  @doc "Interpreta el destinatario: `{:familia, nombre}` o `{:persona, documento}`."
  def tipo_destinatario("familia:" <> familia), do: {:familia, Validacion.normalizar(familia)}
  def tipo_destinatario(documento), do: {:persona, documento}

  def cambiar_estado(%__MODULE__{} = mensaje, nuevo) do
    with :ok <- Transiciones.validar(:mensaje, mensaje.estado, nuevo) do
      {:ok, %{mensaje | estado: nuevo}}
    end
  end

  def a_fila(m), do: [m.id, m.fecha, m.remitente, m.destinatario, m.contenido, m.estado]

  def desde_fila([id, fecha, remitente, destinatario, contenido, estado]) do
    %__MODULE__{
      id: id,
      fecha: Persistencia.a_fecha(fecha),
      remitente: remitente,
      destinatario: destinatario,
      contenido: contenido,
      estado: Persistencia.a_atomo(estado, [:pendiente, :entregado])
    }
  end
end
