defmodule Emergencias.CLI.Parser do
  @moduledoc """
  Convierte una línea escrita por el usuario en `{comando, argumentos, opciones}`.

      register_need agua 30 critica centro "Punto de atención sector 3"
      list_needs zona=centro prioridad=critica

  * Los textos entre comillas (rectas `"` o tipográficas `“ ”`) forman un solo argumento.
  * Los argumentos `clave=valor` sin comillas son opciones (filtros).
    También se admite `clave="valor con espacios"`.
  """

  @comillas ["\"", "“", "”"]

  @doc "Devuelve `{:ok, %{comando, args, opciones}}`, `{:ok, :vacio}` o `{:error, motivo}`."
  def parsear(linea) do
    with {:ok, tokens} <- tokenizar(linea) do
      case tokens do
        [] ->
          {:ok, :vacio}

        [{_tipo, comando} | resto] ->
          {opciones, args} = Enum.split_with(resto, &opcion?/1)

          {:ok,
           %{
             comando: String.downcase(comando),
             args: Enum.map(args, fn {_tipo, texto} -> texto end),
             opciones: Map.new(opciones, &partir_opcion/1)
           }}
      end
    end
  end

  defp opcion?({:texto, texto}), do: Regex.match?(~r/^[a-z_]+=/i, texto)
  defp opcion?({:citado, _texto}), do: false

  defp partir_opcion({:texto, texto}) do
    [clave, valor] = String.split(texto, "=", parts: 2)
    {String.downcase(clave), valor}
  end

  @doc """
  RECURSIVA. Tokenizador carácter a carácter.

  Recorre la lista de grafemas llevando: el token que se está armando (al revés),
  los tokens ya cerrados (al revés) y el modo actual (`:normal` o `{:comillas, prefijo}`).
  Caso base: no quedan caracteres.
  """
  def tokenizar(linea), do: tokenizar(String.graphemes(linea), [], [], :normal)

  defp tokenizar([], actual, tokens, :normal), do: {:ok, Enum.reverse(cerrar(actual, tokens))}
  defp tokenizar([], _actual, _tokens, {:comillas, _}), do: {:error, :comillas_sin_cerrar}

  # Abre comillas: lo que venía antes (por ejemplo `nombre=`) queda como prefijo.
  defp tokenizar([c | resto], actual, tokens, :normal) when c in @comillas do
    tokenizar(resto, [], tokens, {:comillas, texto(actual)})
  end

  # Cierra comillas: con prefijo es una opción `clave=valor`, sin prefijo un argumento citado.
  defp tokenizar([c | resto], actual, tokens, {:comillas, prefijo}) when c in @comillas do
    token =
      if prefijo == "", do: {:citado, texto(actual)}, else: {:texto, prefijo <> texto(actual)}

    tokenizar(resto, [], [token | tokens], :normal)
  end

  defp tokenizar([c | resto], actual, tokens, :normal) when c in [" ", "\t", "\r", "\n"] do
    tokenizar(resto, [], cerrar(actual, tokens), :normal)
  end

  defp tokenizar([c | resto], actual, tokens, modo),
    do: tokenizar(resto, [c | actual], tokens, modo)

  defp cerrar([], tokens), do: tokens
  defp cerrar(actual, tokens), do: [{:texto, texto(actual)} | tokens]

  defp texto(caracteres_al_reves), do: caracteres_al_reves |> Enum.reverse() |> Enum.join()
end
