defmodule Emergencias.Servidores.Usuarios do
  @moduledoc """
  GenServer dueño de los usuarios registrados (`%{username => %Usuario{}}`).

  `conectar/5` aplica la regla del enunciado: si el usuario no existe se registra
  automáticamente; si existe se valida la contraseña. Como todo pasa por el
  mailbox del proceso, dos conexiones simultáneas con un username nuevo nunca
  crean dos usuarios.
  """

  use GenServer

  alias Emergencias.Persistencia
  alias Emergencias.Dominio.Usuario

  @archivo "usuarios.txt"

  # ---------------------------------------------------------------------------
  # API
  # ---------------------------------------------------------------------------

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc "Devuelve `{:ok, usuario, :registrado | :autenticado}` o `{:error, motivo}`."
  def conectar(username, clave, tipo \\ nil, zona \\ nil, nombre \\ nil),
    do: GenServer.call(__MODULE__, {:conectar, username, clave, tipo, zona, nombre})

  def obtener(username), do: GenServer.call(__MODULE__, {:obtener, username})

  @doc "¿Existe un usuario con ese nombre? (sin importar mayúsculas ni espacios)"
  def existe?(username) do
    match?({:ok, _}, obtener(username |> to_string() |> String.trim() |> String.downcase()))
  end

  def listar, do: GenServer.call(__MODULE__, :listar)

  def cambiar_tipo(username, tipo),
    do: GenServer.call(__MODULE__, {:cambiar_tipo, username, tipo})

  def reiniciar, do: GenServer.call(__MODULE__, :reiniciar)

  # ---------------------------------------------------------------------------
  # Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(:ok) do
    usuarios =
      @archivo
      |> Persistencia.leer()
      |> Map.new(fn fila ->
        usuario = Usuario.desde_fila(fila)
        {usuario.username, usuario}
      end)

    {:ok, usuarios}
  end

  @impl true
  def handle_call({:conectar, username, clave, tipo, zona, nombre}, _de, usuarios) do
    clave_mapa = username |> to_string() |> String.trim() |> String.downcase()

    case Map.fetch(usuarios, clave_mapa) do
      {:ok, usuario} ->
        if Usuario.clave_valida?(usuario, clave),
          do: {:reply, {:ok, usuario, :autenticado}, usuarios},
          else: {:reply, {:error, :clave_incorrecta}, usuarios}

      :error ->
        case Usuario.nuevo(username, clave, tipo, zona, nombre) do
          {:ok, usuario} ->
            nuevos = Map.put(usuarios, usuario.username, usuario)
            guardar(nuevos)
            {:reply, {:ok, usuario, :registrado}, nuevos}

          error ->
            {:reply, error, usuarios}
        end
    end
  end

  def handle_call({:obtener, username}, _de, usuarios) do
    case Map.fetch(usuarios, username) do
      {:ok, usuario} -> {:reply, {:ok, usuario}, usuarios}
      :error -> {:reply, {:error, {:no_encontrado, username}}, usuarios}
    end
  end

  def handle_call(:listar, _de, usuarios) do
    {:reply, usuarios |> Map.values() |> Enum.sort_by(& &1.username), usuarios}
  end

  def handle_call({:cambiar_tipo, username, tipo}, _de, usuarios) do
    with {:ok, usuario} <- Map.fetch(usuarios, username) |> encontrado(username),
         {:ok, tipo} <- Usuario.validar_tipo(tipo) do
      actualizado = %{usuario | tipo: tipo}
      nuevos = Map.put(usuarios, username, actualizado)
      guardar(nuevos)
      {:reply, {:ok, actualizado}, nuevos}
    else
      error -> {:reply, error, usuarios}
    end
  end

  def handle_call(:reiniciar, _de, _usuarios) do
    Persistencia.eliminar(@archivo)
    {:reply, :ok, %{}}
  end

  defp encontrado({:ok, valor}, _id), do: {:ok, valor}
  defp encontrado(:error, id), do: {:error, {:no_encontrado, id}}

  defp guardar(usuarios) do
    Persistencia.guardar(@archivo, usuarios |> Map.values() |> Enum.map(&Usuario.a_fila/1))
  end
end
