defmodule Emergencias.Dominio.Recurso do
  @moduledoc """
  Recurso disponible en un centro de apoyo (punto de atención, centro de acopio o albergue).

  `nombre` es el tipo de recurso (agua, arroz, gasas...) y `categoria` permite
  agruparlos (alimentos, medicamentos...). Una necesidad de tipo X puede tomar
  recursos cuyo nombre o categoría sea X.
  """

  alias Emergencias.{Persistencia, Validacion}

  defstruct [:codigo, :nombre, :categoria, :cantidad, :unidad, :ubicacion, :zona, :creado_en]

  def nuevo(attrs) do
    with {:ok, codigo} <- Validacion.identificador(attrs[:codigo] || "", :codigo),
         {:ok, nombre} <- Validacion.texto_requerido(attrs[:nombre], :nombre),
         {:ok, cantidad} <- Validacion.entero_no_negativo(attrs[:cantidad], :cantidad),
         {:ok, unidad} <- Validacion.texto_requerido(attrs[:unidad], :unidad),
         {:ok, ubicacion} <- Validacion.identificador(attrs[:ubicacion] || "", :ubicacion) do
      nombre = Validacion.normalizar(nombre)

      {:ok,
       %__MODULE__{
         codigo: codigo,
         nombre: nombre,
         categoria: categoria(attrs[:categoria], nombre),
         cantidad: cantidad,
         unidad: Validacion.normalizar(unidad),
         ubicacion: ubicacion,
         zona: attrs[:zona],
         creado_en: Persistencia.ahora()
       }}
    end
  end

  defp categoria(nil, nombre), do: nombre
  defp categoria("", nombre), do: nombre
  defp categoria(texto, _nombre), do: Validacion.normalizar(texto)

  @doc "¿El recurso sirve para el tipo pedido? (coincide nombre o categoría)"
  def de_tipo?(%__MODULE__{nombre: nombre, categoria: categoria}, tipo) do
    tipo = Validacion.normalizar(tipo)
    nombre == tipo or categoria == tipo
  end

  @doc "Suma o resta unidades sin permitir cantidades negativas."
  def ajustar(%__MODULE__{cantidad: actual} = recurso, delta) do
    if actual + delta < 0,
      do: {:error, {:inventario_insuficiente, actual}},
      else: {:ok, %{recurso | cantidad: actual + delta}}
  end

  @doc """
  RECURSIVA. Planifica de qué recursos sacar `cantidad` unidades.

  Recorre la lista de candidatos (ya ordenados por preferencia) tomando lo que
  pueda de cada uno hasta completar. Caso base 1: ya no falta nada → plan listo.
  Caso base 2: se acabaron los candidatos y aún falta → inventario insuficiente.
  El plan es todo o nada: si no alcanza, no se toma nada.
  """
  def planificar_retiro(candidatos, cantidad), do: planificar_retiro(candidatos, cantidad, [])

  defp planificar_retiro(_candidatos, 0, plan), do: {:ok, Enum.reverse(plan)}
  defp planificar_retiro([], _faltante, _plan), do: :insuficiente

  defp planificar_retiro([%__MODULE__{cantidad: 0} | resto], faltante, plan),
    do: planificar_retiro(resto, faltante, plan)

  defp planificar_retiro([recurso | resto], faltante, plan) do
    tomado = min(recurso.cantidad, faltante)
    planificar_retiro(resto, faltante - tomado, [{recurso.codigo, tomado} | plan])
  end

  # ---------------------------------------------------------------------------
  # Persistencia
  # ---------------------------------------------------------------------------

  def a_fila(r),
    do: [r.codigo, r.nombre, r.categoria, r.cantidad, r.unidad, r.ubicacion, r.zona, r.creado_en]

  def desde_fila([codigo, nombre, categoria, cantidad, unidad, ubicacion, zona, creado]) do
    %__MODULE__{
      codigo: codigo,
      nombre: nombre,
      categoria: categoria,
      cantidad: Persistencia.a_entero(cantidad),
      unidad: unidad,
      ubicacion: ubicacion,
      zona: Persistencia.a_texto_o_nil(zona),
      creado_en: Persistencia.a_fecha(creado)
    }
  end
end
