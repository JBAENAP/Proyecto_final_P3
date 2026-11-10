defmodule Emergencias.Sesiones.SupervisorSesiones do
  @moduledoc """
  DynamicSupervisor de sesiones: los hijos (uno por usuario conectado) se crean
  y destruyen en tiempo de ejecución, por eso no sirve un Supervisor estático.
  Las sesiones son `:temporary`: si una falla no se reinicia (el usuario
  simplemente debe volver a conectarse) y no afecta a las demás.
  """

  use DynamicSupervisor

  alias Emergencias.Sesiones.Sesion

  def start_link(_opts), do: DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok), do: DynamicSupervisor.init(strategy: :one_for_one)

  @doc "Abre una sesión para `usuario` asociada al proceso `cliente`."
  def abrir(usuario, cliente \\ self()) do
    case DynamicSupervisor.start_child(__MODULE__, {Sesion, {usuario, cliente}}) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, _pid}} -> {:error, :ya_conectado}
      error -> error
    end
  end

  @doc """
  Usernames con sesión activa. El Registry borra la entrada de un proceso
  terminado de forma asíncrona, por eso se filtran los procesos que ya no viven.
  """
  def conectados do
    Emergencias.RegistroSesiones
    |> Registry.select([{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
    |> Enum.filter(fn {_username, pid} -> Process.alive?(pid) end)
    |> Enum.map(fn {username, _pid} -> username end)
    |> Enum.sort()
  end

  def buscar(username) do
    case Registry.lookup(Emergencias.RegistroSesiones, username) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :no_conectado}
    end
  end

  def cerrar_todas do
    __MODULE__
    |> DynamicSupervisor.which_children()
    |> Enum.each(fn {_, pid, _, _} -> DynamicSupervisor.terminate_child(__MODULE__, pid) end)
  end
end
