defmodule Mix.Tasks.Consola do
  @moduledoc """
  Inicia la consola del sistema de emergencias en modo local (una sola VM).

      mix consola                          # menú numerado
      mix consola --comandos               # escribir comandos (connect, register_need...)
      mix consola demo/flujo_ejemplo.txt   # ejecuta un archivo de comandos

  En los dos primeros modos se usan los datos de `datos/` (con los datos de muestra
  de Armenia si está vacía). Un archivo de comandos se ejecuta sobre una carpeta
  temporal vacía, porque el flujo del enunciado espera empezar sin datos (N001, R001...).
  """

  use Mix.Task

  @shortdoc "Inicia la consola del sistema de emergencias"

  @impl true
  def run(args) do
    case args do
      [] ->
        iniciar_con_muestra()
        Emergencias.CLI.Consola.iniciar(:menu)

      ["--comandos" | _] ->
        iniciar_con_muestra()
        Emergencias.CLI.Consola.iniciar(:comandos)

      [ruta | _] ->
        Mix.Task.run("app.config")
        directorio = Path.join(System.tmp_dir!(), "emergencias_flujo")
        File.rm_rf!(directorio)
        Application.put_env(:emergencias, :directorio_datos, directorio)
        Mix.Task.run("app.start")
        Emergencias.CLI.Consola.ejecutar_archivo(ruta)
    end
  end

  defp iniciar_con_muestra do
    Mix.Task.run("app.start")
    Emergencias.DatosIniciales.cargar_al_iniciar()
  end
end
