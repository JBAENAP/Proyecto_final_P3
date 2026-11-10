defmodule Emergencias.SupervisionTest do
  @moduledoc "Supervisión, sesiones (DynamicSupervisor) y persistencia tras reinicios."

  use Emergencias.CasoSistema, async: false

  alias Emergencias.{Bitacora, Persistencia}
  alias Emergencias.Servidores.{Inventario, Necesidades}
  alias Emergencias.Sesiones.{Sesion, SupervisorSesiones}

  defp esperar_reinicio(nombre, pid_anterior, intentos \\ 50) do
    case Process.whereis(nombre) do
      pid when is_pid(pid) and pid != pid_anterior ->
        pid

      _ when intentos > 0 ->
        Process.sleep(20)
        esperar_reinicio(nombre, pid_anterior, intentos - 1)
    end
  end

  test "un GenServer caído se reinicia y recupera su estado desde el archivo" do
    con_demo()
    recurso!("R1", "agua", 77)
    n = necesidad!("agua", 5, "alta")

    pid = Process.whereis(Inventario)
    Process.exit(pid, :kill)
    nuevo = esperar_reinicio(Inventario, pid)

    assert nuevo != pid
    assert {:ok, %{cantidad: 77}} = Inventario.obtener("R1")

    pid_necesidades = Process.whereis(Necesidades)
    Process.exit(pid_necesidades, :kill)
    esperar_reinicio(Necesidades, pid_necesidades)
    assert {:ok, %{id: id}} = Necesidades.obtener(n.id)

    # El contador de identificadores también se recupera: no se repiten ids.
    otra = necesidad!("agua", 1, "baja")
    refute otra.id == id
  end

  test "la caída de un servidor no afecta a los demás (one_for_one)" do
    otros =
      Enum.map(
        [Emergencias.Servidores.Zonas, Emergencias.Servidores.Albergues],
        &Process.whereis/1
      )

    pid = Process.whereis(Inventario)
    Process.exit(pid, :kill)
    esperar_reinicio(Inventario, pid)

    assert Enum.map(
             [Emergencias.Servidores.Zonas, Emergencias.Servidores.Albergues],
             &Process.whereis/1
           ) == otros
  end

  test "la bitácora (proceso sin GenServer) se reinicia y conserva lo registrado" do
    Bitacora.registrar("laura", "prueba", "detalle", "ok")
    assert [{_, "laura", "prueba", "detalle", "ok"}] = Bitacora.consultar("laura")

    pid = Process.whereis(Bitacora)
    Process.exit(pid, :kill)
    esperar_reinicio(Bitacora, pid)

    assert [{_, "laura", "prueba", "detalle", "ok"}] = Bitacora.consultar("laura")
  end

  test "los datos quedan en archivos de texto plano" do
    con_demo()
    recurso!("R1", "agua", 12)

    contenido = File.read!(Persistencia.ruta("recursos.txt"))
    assert contenido =~ "R1|agua|agua|12|unidades|centro_acopio_1|centro|"

    assert File.read!(Persistencia.ruta("zonas.txt")) =~
             "sector_1|Sector 1|sector|alto|400||centro"

    assert File.read!(Persistencia.ruta("movimientos.txt")) =~ "|registro|R1|12|12|"
  end

  describe "sesiones bajo DynamicSupervisor" do
    test "connect crea un proceso de sesión y disconnect lo termina" do
      {:ok, %{sesion: sesion}} = Emergencias.conectar("laura", "1234", "coordinador", "centro")
      assert Process.alive?(sesion)
      assert SupervisorSesiones.conectados() == ["laura"]
      assert Sesion.usuario(sesion).username == "laura"

      {:ok, _} = Emergencias.desconectar(sesion)
      refute Process.alive?(sesion)
      assert SupervisorSesiones.conectados() == []
    end

    test "un usuario no puede tener dos sesiones simultáneas" do
      {:ok, _} = Emergencias.conectar("laura", "1234")
      assert Emergencias.conectar("laura", "1234") == {:error, :ya_conectado}
    end

    test "si el cliente muere la sesión se cierra sola" do
      cliente = spawn(fn -> receive do: (:fin -> :ok) end)
      {:ok, %{sesion: sesion}} = Emergencias.conectar("pedro", "1234", nil, nil, nil, cliente)
      referencia = Process.monitor(sesion)

      send(cliente, :fin)
      assert_receive {:DOWN, ^referencia, :process, ^sesion, _}, 1_000
      assert SupervisorSesiones.conectados() == []
    end

    test "varios usuarios conectados en paralelo" do
      tareas =
        for i <- 1..20 do
          Task.async(fn ->
            {:ok, %{sesion: s}} =
              Emergencias.conectar("usuario#{i}", "1234", "voluntario", "centro")

            s
          end)
        end

      sesiones = Enum.map(tareas, &Task.await/1)
      assert length(Enum.uniq(sesiones)) == 20
      assert length(Emergencias.Servidores.Usuarios.listar()) == 20
    end

    test "un cambio de rol se refleja en la sesión abierta" do
      {:ok, %{sesion: sesion}} = Emergencias.conectar("pedro", "1234", "ciudadano")
      {:ok, _} = Emergencias.cambiar_rol(actor(:administrador), "pedro", "voluntario")
      Process.sleep(20)
      assert Sesion.usuario(sesion).tipo == :voluntario
    end
  end
end
