defmodule Emergencias.Distribucion do
  @moduledoc """
  Arranque de nodos Erlang en un mismo computador.

  * El SERVIDOR es el nodo `servidor@<equipo>`: corre todos los GenServers y es el
    único que escribe en `datos/`.
  * Cada CLIENTE es un nodo `clienteN@<equipo>` (N = 1, 2, 3...) que solo corre la
    consola y ejecuta los comandos en el servidor.

  Los nodos se encuentran a través de `epmd` (Erlang Port Mapper Daemon), que se
  inicia automáticamente al arrancar el servidor con `--sname`. Todos usan la misma
  cookie, requisito de Erlang para que dos nodos se acepten.
  """

  @max_clientes 50

  def cookie, do: Application.get_env(:emergencias, :cookie, :emergencias)

  @doc "Prepara el nodo servidor (si la VM ya arrancó con `--sname`, solo fija la cookie)."
  def iniciar_servidor(nombre \\ "servidor") do
    cond do
      Node.alive?() -> fijar_cookie(node())
      nombre in nombres_registrados() -> {:error, {:nombre_en_uso, nombre}}
      true -> iniciar_nodo(nombre)
    end
  end

  @doc """
  Convierte esta VM en el siguiente `clienteN` libre. Si otro cliente toma el mismo
  nombre en el mismo instante, se reintenta con el siguiente.
  """
  def iniciar_cliente(intentos \\ 3)
  def iniciar_cliente(0), do: {:error, :no_se_pudo_elegir_nombre}

  def iniciar_cliente(intentos) do
    usados = nombres_registrados()

    case Enum.find(1..@max_clientes, &("cliente#{&1}" not in usados)) do
      nil ->
        {:error, :demasiados_clientes}

      n ->
        case iniciar_nodo("cliente#{n}", oculto: true) do
          {:ok, nodo} -> {:ok, nodo}
          {:error, _} -> iniciar_cliente(intentos - 1)
        end
    end
  end

  @doc "Conecta este nodo con el servidor del mismo computador y verifica que esté listo."
  def conectar_servidor(nombre \\ "servidor") do
    servidor = nodo_en_este_equipo(nombre)

    cond do
      Node.connect(servidor) != true -> {:error, {:servidor_no_encontrado, servidor}}
      not servidor_listo?(servidor) -> {:error, {:servidor_sin_aplicacion, servidor}}
      true -> {:ok, servidor}
    end
  end

  @doc "Nombre completo de un nodo en este mismo equipo, por ejemplo `servidor@Juan`."
  def nodo_en_este_equipo(nombre) do
    [_nodo, equipo] = node() |> Atom.to_string() |> String.split("@")
    String.to_atom("#{nombre}@#{equipo}")
  end

  @doc "Nombres de los nodos registrados en el epmd de este equipo."
  def nombres_registrados do
    case :erl_epmd.names() do
      {:ok, nombres} -> MapSet.new(nombres, fn {nombre, _puerto} -> List.to_string(nombre) end)
      {:error, _} -> MapSet.new()
    end
  end

  @doc """
  Convierte esta VM en un nodo con nombre corto. Con `oculto: true` el nodo es
  "oculto": solo se conecta con quien él mismo llama (el servidor) y no forma una
  malla con los demás clientes, que no necesitan hablar entre sí.
  """
  def iniciar_nodo(nombre, opciones \\ []) do
    configuracion = %{name_domain: :shortnames, hidden: Keyword.get(opciones, :oculto, false)}

    with :ok <- asegurar_epmd() do
      case :net_kernel.start(String.to_atom(nombre), configuracion) do
        {:ok, _pid} -> fijar_cookie(node())
        {:error, motivo} -> {:error, {:no_se_pudo_iniciar_nodo, motivo}}
      end
    end
  end

  defp fijar_cookie(nodo) do
    Node.set_cookie(cookie())
    {:ok, nodo}
  end

  defp servidor_listo?(servidor) do
    is_pid(:erpc.call(servidor, Process, :whereis, [Emergencias.Supervisor], 5_000))
  catch
    _tipo, _motivo -> false
  end

  # Si epmd no está corriendo se intenta iniciarlo. En algunos equipos Windows esto
  # no funciona desde una VM ya iniciada; por eso el servidor se arranca con --sname
  # (ver servidor.bat), que siempre lo levanta.
  def asegurar_epmd do
    if epmd_activo?() do
      :ok
    else
      case System.find_executable("epmd") do
        nil ->
          {:error, :epmd_no_disponible}

        epmd ->
          System.cmd(epmd, ["-daemon"], stderr_to_stdout: true)
          esperar_epmd(20)
      end
    end
  end

  defp epmd_activo?, do: match?({:ok, _}, :erl_epmd.names())

  defp esperar_epmd(0), do: {:error, :epmd_no_disponible}

  defp esperar_epmd(intentos) do
    if epmd_activo?() do
      :ok
    else
      Process.sleep(100)
      esperar_epmd(intentos - 1)
    end
  end
end
