defmodule Mix.Tasks.Servidor do
  @moduledoc """
  Inicia el nodo servidor: todos los GenServers, supervisores y la persistencia.
  Muestra en vivo las terminales que se conectan y la actividad de los usuarios.

  Forma recomendada (garantiza que epmd quede corriendo):

      elixir --sname servidor --cookie emergencias -S mix servidor

  o simplemente `servidor.bat` en Windows. Se detiene con Ctrl+C.
  """

  use Mix.Task

  alias Emergencias.Distribucion

  @shortdoc "Inicia el servidor del sistema de emergencias (nodo Erlang)"

  @impl true
  def run(_args) do
    case Distribucion.iniciar_servidor() do
      {:ok, nodo} ->
        Mix.Task.run("app.start")
        # Primero los datos de muestra (sin mostrar su actividad) y luego la actividad en vivo.
        Emergencias.DatosIniciales.cargar_al_iniciar()
        Application.put_env(:emergencias, :mostrar_actividad, true)
        # node_type: :all para enterarse también de los clientes (son nodos ocultos).
        :net_kernel.monitor_nodes(true, node_type: :all)

        IO.puts("""
        ==============================================================
         SERVIDOR del Sistema de Gestión de Emergencias
        ==============================================================
        Nodo: #{nodo}
        Datos: #{Emergencias.Persistencia.directorio()}
        Abra otras terminales en esta carpeta y ejecute: cliente.bat
        (o: mix cliente). Ctrl+C para detener el servidor.
        --------------------------------------------------------------
        """)

        vigilar()

      {:error, motivo} ->
        Mix.raise("""
        No se pudo iniciar el servidor: #{inspect(motivo)}
        Inícielo con: elixir --sname servidor --cookie emergencias -S mix servidor
        """)
    end
  end

  # RECURSIVA: espera para siempre avisando qué terminales se conectan o desconectan.
  defp vigilar do
    receive do
      {:nodeup, nodo, _info} -> IO.puts("[#{hora()}] + terminal conectada: #{nodo}")
      {:nodedown, nodo, _info} -> IO.puts("[#{hora()}] - terminal desconectada: #{nodo}")
    end

    vigilar()
  end

  defp hora, do: Calendar.strftime(NaiveDateTime.local_now(), "%H:%M:%S")
end
