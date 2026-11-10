ExUnit.start()

# Las pruebas distribuidas necesitan epmd activo; si no lo está, se omiten en lugar
# de fallar. (El nodo se nombra después, en setup_all de esas pruebas: hacerlo aquí
# interfiere con el compilador de Mix, que aún está cargando los archivos de prueba.)
case Emergencias.Distribucion.asegurar_epmd() do
  :ok ->
    :ok

  {:error, motivo} ->
    IO.puts("Aviso: se omiten las pruebas distribuidas (#{inspect(motivo)}).")
    IO.puts("Ejecute servidor.bat una vez (inicia epmd) y vuelva a correr mix test.")
    ExUnit.configure(exclude: [:distribuido])
end

defmodule Emergencias.CasoSistema do
  @moduledoc """
  Plantilla para pruebas que usan los procesos del sistema: antes de cada prueba
  borra todos los datos (memoria y archivos del directorio temporal de pruebas).
  Estas pruebas no pueden ser `async` porque comparten los GenServers con nombre.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Emergencias.CasoSistema
    end
  end

  setup do
    :ok = Emergencias.reiniciar_datos()
    :ok
  end

  @doc "Actor sin sesión, útil para llamar la fachada directamente."
  def actor(tipo, username \\ nil) do
    %Emergencias.Dominio.Usuario{
      username: username || "#{tipo}_prueba",
      tipo: tipo,
      zona: "centro",
      nombre_completo: "Usuario de prueba"
    }
  end

  @doc "Carga zonas, sectores, puntos y albergues de ejemplo."
  def con_demo do
    {:ok, _} = Emergencias.cargar_demo(actor(:administrador))
    :ok
  end

  def recurso!(codigo, nombre, cantidad, ubicacion \\ "centro_acopio_1") do
    {:ok, recurso} =
      Emergencias.registrar_recurso(actor(:coordinador), %{
        codigo: codigo,
        nombre: nombre,
        cantidad: cantidad,
        unidad: "unidades",
        ubicacion: ubicacion
      })

    recurso
  end

  def necesidad!(tipo, cantidad, prioridad \\ "media", zona \\ "centro") do
    {:ok, necesidad} =
      Emergencias.registrar_necesidad(actor(:coordinador), %{
        tipo: tipo,
        cantidad: cantidad,
        prioridad: prioridad,
        zona: zona,
        descripcion: "prueba"
      })

    necesidad
  end
end
