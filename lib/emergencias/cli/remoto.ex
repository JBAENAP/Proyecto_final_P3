defmodule Emergencias.CLI.Remoto do
  @moduledoc """
  Puente entre la consola y la fachada `Emergencias`.

  * Modo local (`mix consola` y pruebas): llama a `Emergencias` en esta misma VM.
  * Modo distribuido (`mix cliente`): ejecuta la función en el nodo servidor con
    `:erpc.call/5`. Los argumentos y resultados (structs, MapSet, pids) viajan entre
    nodos sin conversión porque ambos tienen el mismo código.

  Por cada función pública de `Emergencias` se genera aquí, al compilar, una función
  con el mismo nombre y aridad que delega en `llamar/2`. Así la consola usa siempre
  `Remoto.registrar_zona(...)` sin saber en qué modo está.
  """

  alias Emergencias.Sesiones.Sesion

  @tiempo_maximo 60_000

  # Funciones de la fachada que la consola nunca debe ejecutar.
  @excluidas [reiniciar_datos: 0, validar_filtros: 2]

  for {funcion, aridad} <- Emergencias.__info__(:functions),
      {funcion, aridad} not in @excluidas do
    argumentos = Macro.generate_arguments(aridad, __MODULE__)

    def unquote(funcion)(unquote_splicing(argumentos)),
      do: llamar(unquote(funcion), unquote(argumentos))
  end

  @doc "Nodo servidor configurado, o `nil` en modo local."
  def servidor, do: Application.get_env(:emergencias, :nodo_servidor)

  def llamar(funcion, argumentos) do
    case servidor() do
      nil -> apply(Emergencias, funcion, argumentos)
      nodo -> llamar_remoto(nodo, funcion, argumentos)
    end
  end

  defp llamar_remoto(nodo, funcion, argumentos) do
    :erpc.call(nodo, Emergencias, funcion, argumentos, @tiempo_maximo)
  catch
    :error, {:erpc, motivo} -> {:error, {:servidor_no_disponible, motivo}}
    :exit, motivo -> {:error, {:fallo_remoto, motivo}}
  end

  @doc """
  Usuario de una sesión o `nil` si la sesión ya no existe (cerrada, o el servidor
  se cayó). El pid de la sesión puede estar en otro nodo: `GenServer.call/2` funciona
  igual con pids remotos.
  """
  def usuario_sesion(nil), do: nil

  def usuario_sesion(sesion) do
    Sesion.usuario(sesion)
  catch
    :exit, _motivo -> nil
  end

  def contar_comando(sesion), do: Sesion.contar_comando(sesion)
end
