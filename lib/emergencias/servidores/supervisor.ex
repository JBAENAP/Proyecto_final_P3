defmodule Emergencias.Servidores.Supervisor do
  @moduledoc """
  Supervisor de los GenServers del dominio.

  Estrategia `:one_for_one`: cada servidor es dueño de datos independientes y
  recarga su estado desde su archivo al reiniciarse, así que la caída de uno no
  obliga a reiniciar a los demás. `Inventario` se inicia antes que `Necesidades`
  porque esta última le hace llamadas.
  """

  use Supervisor

  alias Emergencias.Servidores.{
    Albergues,
    Familias,
    Inventario,
    Mascotas,
    Necesidades,
    Usuarios,
    Zonas
  }

  def start_link(_opts), do: Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok) do
    children = [Usuarios, Zonas, Inventario, Necesidades, Familias, Mascotas, Albergues]
    Supervisor.init(children, strategy: :one_for_one, max_restarts: 10, max_seconds: 5)
  end
end
