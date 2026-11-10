defmodule Emergencias.Validacion do
  @moduledoc """
  Validaciones puras de entradas de usuario.

  Todas retornan `{:ok, valor}` o `{:error, motivo}`; nunca lanzan excepciones
  para situaciones esperadas, así se pueden encadenar con `with`.
  """

  @doc """
  Normaliza un texto para comparaciones: minúsculas, sin tildes ni espacios extremos.

      iex> Emergencias.Validacion.normalizar("  Crítica ")
      "critica"
  """
  def normalizar(nil), do: ""

  def normalizar(texto) when is_binary(texto) do
    texto
    |> String.trim()
    |> String.downcase()
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
  end

  def normalizar(otro), do: otro |> to_string() |> normalizar()

  @doc "Entero mayor o igual a cero (acepta enteros o texto)."
  def entero_no_negativo(valor, campo) do
    case a_entero(valor) do
      {:ok, n} when n >= 0 -> {:ok, n}
      {:ok, _} -> {:error, {:negativo, campo}}
      :error -> {:error, {:no_numerico, campo}}
    end
  end

  @doc "Entero estrictamente positivo."
  def entero_positivo(valor, campo) do
    case a_entero(valor) do
      {:ok, n} when n > 0 -> {:ok, n}
      {:ok, _} -> {:error, {:debe_ser_positivo, campo}}
      :error -> {:error, {:no_numerico, campo}}
    end
  end

  defp a_entero(n) when is_integer(n), do: {:ok, n}

  defp a_entero(texto) when is_binary(texto) do
    case Integer.parse(String.trim(texto)) do
      {n, ""} -> {:ok, n}
      _ -> :error
    end
  end

  defp a_entero(_), do: :error

  @doc "Texto no vacío (se recorta)."
  def texto_requerido(valor, campo) when is_binary(valor) do
    case String.trim(valor) do
      "" -> {:error, {:requerido, campo}}
      texto -> {:ok, texto}
    end
  end

  def texto_requerido(_valor, campo), do: {:error, {:requerido, campo}}

  @doc """
  Identificador: letras, números, `_` y `-` (sin espacios), de 1 a 40 caracteres.
  """
  def identificador(valor, campo) when is_binary(valor) do
    texto = String.trim(valor)

    if Regex.match?(~r/^[A-Za-z0-9_\-]{1,40}$/, texto),
      do: {:ok, texto},
      else: {:error, {:identificador_invalido, campo}}
  end

  def identificador(_valor, campo), do: {:error, {:identificador_invalido, campo}}

  @doc """
  Traduce un texto a una opción de un catálogo `%{"texto" => :atomo}`.
  El texto se normaliza antes de buscarlo (mayúsculas y tildes no importan).
  """
  def opcion(valor, catalogo, campo) do
    case Map.fetch(catalogo, normalizar(valor)) do
      {:ok, atomo} -> {:ok, atomo}
      :error -> {:error, {:opcion_invalida, campo, catalogo |> Map.values() |> Enum.uniq()}}
    end
  end

  @doc "Valor opcional: si viene `nil` o vacío devuelve el valor por defecto."
  def opcional(nil, defecto, _validador), do: {:ok, defecto}
  def opcional("", defecto, _validador), do: {:ok, defecto}
  def opcional(valor, _defecto, validador), do: validador.(valor)
end
