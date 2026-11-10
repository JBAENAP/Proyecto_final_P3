defmodule Mix.Tasks.Cliente do
  @moduledoc """
  Abre una terminal de usuario conectada al servidor del mismo computador.

      mix cliente              # menú numerado
      mix cliente --comandos   # escribir comandos

  Esta VM NO inicia los GenServers (no arranca la aplicación): se convierte en el
  nodo `clienteN`, se conecta a `servidor` y ejecuta cada comando allá. Se pueden
  abrir tantas terminales como usuarios se quieran simular.
  """

  use Mix.Task

  alias Emergencias.Distribucion

  @shortdoc "Abre una terminal de usuario conectada al servidor"

  @impl true
  def run(args) do
    modo = if "--comandos" in args, do: :comandos, else: :menu

    # Compila y carga la configuración, pero no inicia la aplicación.
    Mix.Task.run("app.config")

    with {:ok, _nodo} <- Distribucion.iniciar_cliente(),
         {:ok, servidor} <- Distribucion.conectar_servidor() do
      Application.put_env(:emergencias, :nodo_servidor, servidor)
      Emergencias.CLI.Consola.iniciar(modo)
    else
      {:error, {:servidor_no_encontrado, servidor}} ->
        Mix.raise("""
        No se encontró el servidor #{servidor}.
        Abra primero otra terminal en esta carpeta y ejecute: servidor.bat
        """)

      {:error, {:servidor_sin_aplicacion, servidor}} ->
        Mix.raise(
          "El nodo #{servidor} existe pero no está ejecutando el sistema (use mix servidor)."
        )

      {:error, motivo} ->
        Mix.raise("""
        No se pudo iniciar la terminal cliente: #{inspect(motivo)}
        ¿Está corriendo el servidor? Ejecute servidor.bat en otra terminal.
        """)
    end
  end
end
