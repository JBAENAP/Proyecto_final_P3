defmodule Emergencias.Dominio.Albergue do
  @moduledoc """
  Albergue con capacidad máxima. `ocupacion` es el total de personas alojadas
  (incluye la ocupación inicial sin documentar) y `ocupantes` es un MapSet con los
  documentos registrados, para impedir que alguien ingrese dos veces.
  """

  alias Emergencias.{Persistencia, Validacion}

  defstruct [
    :codigo,
    :nombre,
    :zona,
    :capacidad,
    :creado_en,
    ocupacion: 0,
    ocupantes: MapSet.new()
  ]

  def nuevo(attrs) do
    with {:ok, codigo} <- Validacion.identificador(attrs[:codigo] || "", :codigo),
         {:ok, nombre} <- Validacion.texto_requerido(attrs[:nombre], :nombre),
         {:ok, zona} <- Validacion.identificador(attrs[:zona] || "", :zona),
         {:ok, capacidad} <- Validacion.entero_positivo(attrs[:capacidad], :capacidad),
         {:ok, ocupacion} <-
           Validacion.opcional(
             attrs[:ocupacion],
             0,
             &Validacion.entero_no_negativo(&1, :ocupacion)
           ),
         :ok <- validar_cupo(ocupacion, capacidad) do
      {:ok,
       %__MODULE__{
         codigo: codigo,
         nombre: nombre,
         zona: zona,
         capacidad: capacidad,
         ocupacion: ocupacion,
         creado_en: Persistencia.ahora()
       }}
    end
  end

  defp validar_cupo(ocupacion, capacidad) when ocupacion <= capacidad, do: :ok
  defp validar_cupo(_ocupacion, capacidad), do: {:error, {:capacidad_superada, capacidad}}

  def cupos(%__MODULE__{capacidad: capacidad, ocupacion: ocupacion}), do: capacidad - ocupacion

  def porcentaje(%__MODULE__{capacidad: capacidad, ocupacion: ocupacion}),
    do: Float.round(ocupacion * 100 / capacidad, 1)

  @doc "Ingreso de una persona: nunca supera la capacidad ni admite duplicados."
  def ingresar(%__MODULE__{} = albergue, documento) do
    cond do
      MapSet.member?(albergue.ocupantes, documento) ->
        {:error, {:ya_esta_en_albergue, documento}}

      cupos(albergue) <= 0 ->
        {:error, {:capacidad_superada, albergue.capacidad}}

      true ->
        {:ok,
         %{
           albergue
           | ocupacion: albergue.ocupacion + 1,
             ocupantes: MapSet.put(albergue.ocupantes, documento)
         }}
    end
  end

  def salir(%__MODULE__{} = albergue, documento) do
    if MapSet.member?(albergue.ocupantes, documento) do
      {:ok,
       %{
         albergue
         | ocupacion: albergue.ocupacion - 1,
           ocupantes: MapSet.delete(albergue.ocupantes, documento)
       }}
    else
      {:error, {:no_esta_en_albergue, documento}}
    end
  end

  @doc """
  RECURSIVA. Los `n` albergues con mayor porcentaje de ocupación.

  Recorre la lista una sola vez e inserta cada albergue en un ranking ordenado
  que nunca supera `n` elementos (no hace falta ordenar toda la lista).
  """
  def top(albergues, n), do: top(albergues, n, [])

  defp top([], _n, ranking), do: ranking

  defp top([albergue | resto], n, ranking) do
    top(resto, n, ranking |> insertar_ordenado(albergue) |> Enum.take(n))
  end

  # RECURSIVA. Inserción en una lista ordenada de mayor a menor ocupación.
  defp insertar_ordenado([], albergue), do: [albergue]

  defp insertar_ordenado([primero | resto] = lista, albergue) do
    if porcentaje(albergue) > porcentaje(primero),
      do: [albergue | lista],
      else: [primero | insertar_ordenado(resto, albergue)]
  end

  def a_fila(a) do
    [
      a.codigo,
      a.nombre,
      a.zona,
      a.capacidad,
      a.ocupacion,
      a.ocupantes |> MapSet.to_list() |> Persistencia.de_lista(),
      a.creado_en
    ]
  end

  def desde_fila([codigo, nombre, zona, capacidad, ocupacion, ocupantes, creado]) do
    %__MODULE__{
      codigo: codigo,
      nombre: nombre,
      zona: zona,
      capacidad: Persistencia.a_entero(capacidad),
      ocupacion: Persistencia.a_entero(ocupacion),
      ocupantes: ocupantes |> Persistencia.a_lista() |> MapSet.new(),
      creado_en: Persistencia.a_fecha(creado)
    }
  end
end
