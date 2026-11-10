defmodule Emergencias.DistribuidoTest do
  @moduledoc """
  Pruebas con nodos Erlang reales: el nodo de pruebas hace de SERVIDOR y cada
  "terminal" es un nodo aparte creado con `:peer` (otra VM en el mismo computador)
  que ejecuta la consola contra el servidor, igual que `mix cliente`.
  """

  use Emergencias.CasoSistema, async: false

  @moduletag :distribuido

  alias Emergencias.CLI.{Comandos, Remoto}
  alias Emergencias.Sesiones.SupervisorSesiones

  # Inicia una VM nueva con el código del proyecto y la configura como cliente.
  defp abrir_terminal(nombre) do
    rutas = Enum.flat_map(:code.get_path(), &[~c"-pa", &1])
    cookie = ~c"-setcookie " ++ Atom.to_charlist(Node.get_cookie())

    {:ok, peer, nodo} =
      :peer.start_link(%{
        name: :"#{nombre}_#{System.unique_integer([:positive])}",
        args: rutas ++ [~c"-hidden" | :string.split(cookie, ~c" ")]
      })

    {:ok, _} = :erpc.call(nodo, Application, :ensure_all_started, [:elixir])
    :ok = :erpc.call(nodo, Application, :put_env, [:emergencias, :nodo_servidor, node()])
    {peer, nodo}
  end

  defp en_terminal(nodo, lineas) do
    {salidas, _estado} = :erpc.call(nodo, Comandos, :ejecutar_lineas, [lineas], 30_000)
    salidas
  end

  defp esperar(condicion, intentos \\ 50) do
    cond do
      condicion.() ->
        true

      intentos == 0 ->
        false

      true ->
        Process.sleep(50)
        esperar(condicion, intentos - 1)
    end
  end

  setup_all do
    {:ok, _nodo} = Emergencias.Distribucion.iniciar_nodo("pruebas_emergencias")
    :ok
  end

  setup do
    con_demo()
    {_peer_a, a} = abrir_terminal("terminal_a")
    {_peer_b, b} = abrir_terminal("terminal_b")
    %{a: a, b: b}
  end

  test "la terminal cliente ejecuta los comandos en el servidor", %{a: a} do
    assert :erpc.call(a, Remoto, :servidor, []) == node()
    refute :erpc.call(a, Process, :whereis, [Emergencias.Servidores.Inventario])

    [_, salida] =
      en_terminal(a, [
        "connect laura 1234 coordinador centro",
        "register_resource R001 agua 50 litros centro_acopio_1"
      ])

    assert salida =~ "Recurso R001 registrado"
    assert {:ok, %{cantidad: 50}} = Emergencias.Servidores.Inventario.obtener("R001")
  end

  test "dos terminales comparten el mismo estado", %{a: a, b: b} do
    en_terminal(a, [
      "connect laura 1234 coordinador centro",
      "register_resource R001 agua 50 litros centro_acopio_1"
    ])

    [_, listado] = en_terminal(b, ["connect pedro 1234 voluntario", "list_resources"])
    assert listado =~ "R001"
    assert listado =~ "50"
  end

  test "conflicto concurrente entre dos terminales: nunca se asignan 55 de 50", %{a: a, b: b} do
    recurso!("R001", "agua", 50)
    n1 = necesidad!("agua", 30, "critica")
    n2 = necesidad!("agua", 25, "alta")

    [salida_a, salida_b] =
      [
        {a, ["connect laura 1234 coordinador centro", "assign_resource #{n1.id} agua 30"]},
        {b, ["connect carlos 1234 coordinador centro", "assign_resource #{n2.id} agua 25"]}
      ]
      |> Enum.map(fn {nodo, lineas} -> Task.async(fn -> en_terminal(nodo, lineas) end) end)
      |> Enum.map(&Task.await(&1, 30_000))
      |> Enum.map(&List.last/1)

    asignaciones = [salida_a, salida_b]
    assert Enum.count(asignaciones, &(&1 =~ "Asignado a")) == 1
    assert Enum.count(asignaciones, &(&1 =~ "inventario insuficiente")) == 1
    {:ok, recurso} = Emergencias.Servidores.Inventario.obtener("R001")
    assert recurso.cantidad in [20, 25]
  end

  test "si se cierra la terminal, su sesión se cierra en el servidor" do
    {peer, nodo} = abrir_terminal("terminal_c")

    # Un proceso de larga vida en la terminal hace de "consola" abierta.
    consola = Node.spawn(nodo, Process, :sleep, [:infinity])

    {:ok, %{usuario: %{username: "juan"}}} =
      :erpc.call(nodo, Remoto, :conectar, ["juan", "1234", "voluntario", "centro", nil, consola])

    assert "juan" in SupervisorSesiones.conectados()

    :peer.stop(peer)
    assert esperar(fn -> "juan" not in SupervisorSesiones.conectados() end)
  end
end
