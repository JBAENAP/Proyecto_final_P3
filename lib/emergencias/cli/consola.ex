defmodule Emergencias.CLI.Consola do
  @moduledoc """
  Consola interactiva. Tiene dos modos:

    * `:menu` (por defecto): menú numerado, ver `CLI.Menu`.
    * `:comandos`: REPL donde se escriben los comandos. El ciclo leer → ejecutar →
      imprimir es una función recursiva que lleva el estado de la consola (la
      sesión abierta) como argumento.

  También puede ejecutar un archivo de comandos (uno por línea, `#` para
  comentarios), útil para la demostración: `mix consola demo/flujo_ejemplo.txt`.
  """

  alias Emergencias.CLI.{Comandos, Menu}

  @salir ["exit", "quit", "salir"]

  def iniciar(modo \\ :menu) do
    donde =
      case Emergencias.CLI.Remoto.servidor() do
        nil -> "Modo local (todo en esta terminal)"
        servidor -> "Terminal #{node()} conectada al servidor #{servidor}"
      end

    instrucciones =
      case modo do
        :menu -> "Elija una opción escribiendo su número y presione Enter."
        :comandos -> "Escriba 'help' para ver los comandos y 'exit' para salir."
      end

    IO.puts("""
    ==============================================================
     Sistema de Coordinación y Gestión de Emergencias - Terremoto
    ==============================================================
    #{donde}
    #{instrucciones}
    """)

    estado_final =
      case modo do
        :menu -> Menu.iniciar(Comandos.estado_inicial())
        :comandos -> bucle(Comandos.estado_inicial())
      end

    terminar(estado_final)
  end

  # RECURSIVA: cada iteración lee una línea y se llama a sí misma con el nuevo estado.
  # Devuelve el estado final al salir.
  defp bucle(estado) do
    case IO.gets(prompt(estado)) do
      :eof ->
        estado

      {:error, _motivo} ->
        estado

      linea ->
        linea = String.trim(linea)

        if String.downcase(linea) in @salir do
          estado
        else
          {nuevo, salida} = Comandos.ejecutar(linea, estado)
          if salida != "", do: IO.puts(salida)
          bucle(nuevo)
        end
    end
  end

  @doc "Ejecuta los comandos de un archivo mostrando cada uno antes de su resultado."
  def ejecutar_archivo(ruta) do
    case File.read(ruta) do
      {:ok, contenido} ->
        estado =
          contenido
          |> String.split(["\r\n", "\n"])
          |> Enum.map(&String.trim/1)
          |> Enum.reject(
            &(&1 == "" or String.starts_with?(&1, "#") or String.downcase(&1) in @salir)
          )
          |> Enum.reduce(Comandos.estado_inicial(), fn linea, estado ->
            IO.puts("\n#{prompt(estado)}#{linea}")
            {nuevo, salida} = Comandos.ejecutar(linea, estado)
            if salida != "", do: IO.puts(salida)
            nuevo
          end)

        terminar(estado)

      {:error, motivo} ->
        IO.puts("No se pudo leer #{ruta}: #{:file.format_error(motivo)}")
    end
  end

  defp terminar(%{sesion: nil}), do: IO.puts("Hasta pronto.")

  defp terminar(estado) do
    {_, salida} = Comandos.ejecutar("disconnect", estado)
    IO.puts(salida)
    IO.puts("Hasta pronto.")
  end

  defp prompt(estado) do
    case Comandos.usuario_actual(estado) do
      nil -> "emergencias> "
      u -> "#{u.username}@#{u.tipo}> "
    end
  end
end
