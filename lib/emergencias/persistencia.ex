defmodule Emergencias.Persistencia do
  @moduledoc """
  Persistencia en archivos de texto plano.

  Cada registro ocupa una línea y sus campos se separan con `|`.
  Para que un campo pueda contener `|`, saltos de línea o `\\`, se escapan así:

      \\   ->  \\\\
      |   ->  \\p
      \\n  ->  \\n

  Las tablas completas se reescriben de forma atómica (archivo temporal + rename)
  y los historiales (movimientos, actividad, cambios de estado) se agregan al final.
  """

  @separador "|"

  # ---------------------------------------------------------------------------
  # Rutas
  # ---------------------------------------------------------------------------

  def directorio do
    Application.get_env(:emergencias, :directorio_datos, "datos") |> Path.expand()
  end

  def ruta(archivo), do: Path.join(directorio(), archivo)

  # ---------------------------------------------------------------------------
  # Lectura y escritura
  # ---------------------------------------------------------------------------

  @doc "Lee un archivo y devuelve una lista de filas (cada fila es una lista de campos)."
  def leer(archivo) do
    case File.read(ruta(archivo)) do
      {:ok, contenido} ->
        contenido
        |> String.split(["\r\n", "\n"], trim: true)
        |> Enum.map(&decodificar_linea/1)

      {:error, _motivo} ->
        []
    end
  end

  @doc "Reescribe por completo un archivo con las filas dadas."
  def guardar(archivo, filas) do
    destino = ruta(archivo)
    temporal = destino <> ".tmp"
    contenido = Enum.map(filas, fn fila -> [codificar_linea(fila), "\n"] end)

    with :ok <- File.mkdir_p(directorio()),
         :ok <- File.write(temporal, contenido),
         :ok <- File.rename(temporal, destino) do
      :ok
    end
  end

  @doc "Agrega una fila al final del archivo (historiales)."
  def agregar(archivo, fila) do
    with :ok <- File.mkdir_p(directorio()) do
      File.write(ruta(archivo), [codificar_linea(fila), "\n"], [:append])
    end
  end

  @doc "Elimina un archivo de datos (se usa al reiniciar el sistema en pruebas)."
  def eliminar(archivo) do
    case File.rm(ruta(archivo)) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      otro -> otro
    end
  end

  # ---------------------------------------------------------------------------
  # Codificación de líneas
  # ---------------------------------------------------------------------------

  def codificar_linea(campos) do
    campos
    |> Enum.map(&a_texto/1)
    |> Enum.map(&escapar/1)
    |> Enum.join(@separador)
  end

  def decodificar_linea(linea) do
    linea
    |> String.split(@separador)
    |> Enum.map(&desescapar/1)
  end

  defp escapar(texto) do
    texto
    |> String.replace("\\", "\\\\")
    |> String.replace("|", "\\p")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "")
  end

  @doc """
  Deshace el escape de un campo. Recorre el texto recursivamente, grafema a grafema:
  caso base la cadena vacía; si encuentra `\\` interpreta el siguiente carácter.
  """
  def desescapar(texto), do: desescapar(texto, [])

  defp desescapar("", acumulado), do: acumulado |> Enum.reverse() |> IO.iodata_to_binary()
  defp desescapar("\\\\" <> resto, acumulado), do: desescapar(resto, ["\\" | acumulado])
  defp desescapar("\\p" <> resto, acumulado), do: desescapar(resto, ["|" | acumulado])
  defp desescapar("\\n" <> resto, acumulado), do: desescapar(resto, ["\n" | acumulado])

  defp desescapar(texto, acumulado) do
    {grafema, resto} = String.next_grapheme(texto)
    desescapar(resto, [grafema | acumulado])
  end

  # ---------------------------------------------------------------------------
  # Conversión de valores a texto y de texto a valores
  # ---------------------------------------------------------------------------

  def a_texto(nil), do: ""
  def a_texto(valor) when is_binary(valor), do: valor
  def a_texto(valor) when is_atom(valor), do: Atom.to_string(valor)
  def a_texto(valor) when is_integer(valor), do: Integer.to_string(valor)
  def a_texto(%NaiveDateTime{} = fecha), do: NaiveDateTime.to_iso8601(fecha)
  def a_texto(valor), do: to_string(valor)

  def a_entero(""), do: 0
  def a_entero(texto), do: String.to_integer(texto)

  def a_entero_o_nil(""), do: nil
  def a_entero_o_nil(texto), do: String.to_integer(texto)

  def a_texto_o_nil(""), do: nil
  def a_texto_o_nil(texto), do: texto

  def a_fecha(""), do: nil
  def a_fecha(texto), do: NaiveDateTime.from_iso8601!(texto)

  @doc "Convierte texto a uno de los átomos permitidos (nunca crea átomos nuevos)."
  def a_atomo("", _permitidos), do: nil

  def a_atomo(texto, permitidos) do
    Enum.find(permitidos, fn atomo -> Atom.to_string(atomo) == texto end)
  end

  @doc "Lista de textos separados por `;` (por ejemplo los ocupantes de un albergue)."
  def a_lista(""), do: []
  def a_lista(texto), do: String.split(texto, ";")

  def de_lista(lista), do: Enum.join(lista, ";")

  def ahora, do: NaiveDateTime.local_now()
end
