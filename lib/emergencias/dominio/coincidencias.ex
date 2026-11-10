defmodule Emergencias.Dominio.Coincidencias do
  @moduledoc """
  Algoritmo de similitud entre un reporte de mascota perdida y uno de mascota encontrada.

  Puntaje de 0 a 100 definido por el equipo:

  | Atributo         | Puntos | Criterio                                                        |
  |------------------|--------|-----------------------------------------------------------------|
  | especie          | 30     | obligatoria: si difiere el puntaje total es 0                   |
  | color            | 20     | Jaccard sobre las raíces de las palabras ("negra" ~ "negro")   |
  | tamaño           | 15     | igual 15, tamaño vecino 7                                       |
  | zona             | 15     | misma zona 15, misma zona raíz (sector de la misma zona) 8     |
  | nombre           | 10     | igual 10, alguno desconocido 5, distinto 0                      |
  | características  | 10     | Jaccard sobre el conjunto de palabras significativas           |

  Las comparaciones de conjuntos se hacen con `MapSet` (intersección / unión).
  """

  alias Emergencias.Dominio.Mascota
  alias Emergencias.Validacion

  @doc """
  Calcula `{puntaje, detalle}` entre dos reportes.
  `raices` es un mapa opcional `codigo_zona => codigo_zona_raiz`.
  """
  def puntaje(%Mascota{} = a, %Mascota{} = b, raices \\ %{}) do
    if a.especie != b.especie do
      {0, %{especie: 0}}
    else
      detalle = %{
        especie: 30,
        color: round(20 * jaccard(raices_palabras(a.color), raices_palabras(b.color))),
        tamano: puntaje_tamano(a.tamano, b.tamano),
        zona: puntaje_zona(a.zona, b.zona, raices),
        nombre: puntaje_nombre(a.nombre, b.nombre),
        caracteristicas:
          round(10 * jaccard(palabras(a.caracteristicas), palabras(b.caracteristicas)))
      }

      {detalle |> Map.values() |> Enum.sum(), detalle}
    end
  end

  @doc """
  Compara cada reporte perdido contra todos los encontrados y devuelve los pares
  cuyo puntaje alcanza el umbral, ordenados de mayor a menor.
  """
  def buscar(perdidas, encontradas, umbral, raices \\ %{}) do
    perdidas
    |> Enum.flat_map(&comparar_con_todas(&1, encontradas, umbral, raices))
    |> ordenar()
  end

  @doc "Compara un reporte perdido contra la lista de encontrados (se ejecuta en paralelo por reporte)."
  def comparar_con_todas(perdida, encontradas, umbral, raices) do
    Enum.flat_map(encontradas, fn encontrada ->
      case puntaje(perdida, encontrada, raices) do
        {total, detalle} when total >= umbral ->
          [%{perdida: perdida.id, encontrada: encontrada.id, puntaje: total, detalle: detalle}]

        _ ->
          []
      end
    end)
  end

  def ordenar(coincidencias),
    do: Enum.sort_by(coincidencias, &{-&1.puntaje, &1.perdida, &1.encontrada})

  # ---------------------------------------------------------------------------
  # Criterios
  # ---------------------------------------------------------------------------

  defp puntaje_tamano(igual, igual), do: 15
  defp puntaje_tamano(a, b), do: if(abs(indice_tamano(a) - indice_tamano(b)) == 1, do: 7, else: 0)

  defp indice_tamano(:pequeno), do: 0
  defp indice_tamano(:mediano), do: 1
  defp indice_tamano(:grande), do: 2

  defp puntaje_zona(igual, igual, _raices), do: 15

  defp puntaje_zona(a, b, raices) do
    raiz_a = Map.get(raices, a, a)
    if raiz_a != nil and raiz_a == Map.get(raices, b, b), do: 8, else: 0
  end

  defp puntaje_nombre(nil, _), do: 5
  defp puntaje_nombre(_, nil), do: 5

  defp puntaje_nombre(a, b),
    do: if(Validacion.normalizar(a) == Validacion.normalizar(b), do: 10, else: 0)

  @doc "Índice de Jaccard |A ∩ B| / |A ∪ B| entre dos MapSet (0.0 si ambos están vacíos)."
  def jaccard(a, b) do
    union = MapSet.union(a, b) |> MapSet.size()
    if union == 0, do: 0.0, else: MapSet.size(MapSet.intersection(a, b)) / union
  end

  @doc "Palabras significativas (3+ letras) normalizadas."
  def palabras(texto) do
    texto
    |> Validacion.normalizar()
    |> String.split(~r/[^a-z0-9]+/, trim: true)
    |> Enum.filter(&(String.length(&1) >= 3))
    |> MapSet.new()
  end

  # Raíz simple para colores: se quita la vocal final de género ("negra"/"negro" -> "negr").
  defp raices_palabras(texto) do
    texto
    |> Validacion.normalizar()
    |> String.split(~r/[^a-z0-9]+/, trim: true)
    |> Enum.map(&String.replace(&1, ~r/[aoes]$/, ""))
    |> MapSet.new()
  end
end
