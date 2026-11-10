defmodule Emergencias.CLITest do
  use Emergencias.CasoSistema, async: false

  alias Emergencias.CLI.{Comandos, Parser}
  alias Emergencias.Permisos

  describe "parser" do
    test "argumentos, comillas y opciones" do
      assert {:ok,
              %{
                comando: "register_need",
                args: ["agua", "30", "critica", "centro", "Punto de atención sector 3"],
                opciones: %{}
              }} =
               Parser.parsear(
                 ~s(register_need agua 30 critica centro "Punto de atención sector 3")
               )

      assert {:ok,
              %{
                comando: "list_needs",
                args: [],
                opciones: %{"zona" => "centro", "prioridad" => "critica"}
              }} =
               Parser.parsear("list_needs zona=centro prioridad=critica")

      assert {:ok, %{opciones: %{"nombre" => "Ana María"}}} =
               Parser.parsear(~s(search_persons nombre="Ana María"))

      assert {:ok, %{args: ["Luna"]}} = Parser.parsear("x “Luna”")
      assert {:ok, %{args: ["a=b"]}} = Parser.parsear(~s(x "a=b"))
      assert Parser.parsear(~s(x "sin cerrar)) == {:error, :comillas_sin_cerrar}
      assert Parser.parsear("   ") == {:ok, :vacio}
    end
  end

  describe "permisos" do
    test "herencia de roles" do
      assert Permisos.permitido?(:ciudadano, :report_person)
      refute Permisos.permitido?(:ciudadano, :register_entry)
      assert Permisos.permitido?(:voluntario, :register_entry)
      refute Permisos.permitido?(:voluntario, :assign_resource)
      assert Permisos.permitido?(:coordinador, :assign_resource)
      refute Permisos.permitido?(:coordinador, :set_role)
      assert MapSet.subset?(Permisos.permisos(:coordinador), Permisos.permisos(:administrador))
    end
  end

  describe "comandos" do
    defp correr(lineas) do
      Enum.map_reduce(lineas, Comandos.estado_inicial(), fn linea, estado ->
        {nuevo, salida} = Comandos.ejecutar(linea, estado)
        {salida, nuevo}
      end)
    end

    test "flujo básico por consola" do
      {salidas, estado} =
        correr([
          "summary",
          "connect laura 1234 coordinador centro",
          "connect otra 1234",
          "load_demo",
          ~s(register_need agua 30 critica centro "Punto de atención sector 3"),
          "register_resource R001 agua 50 litros centro_acopio_1",
          "assign_resource N001 agua 30",
          "assign_resource N001 agua 1",
          "list_needs zona=centro prioridad=critica",
          "register_zone",
          "comando_raro",
          "summary"
        ])

      [
        sin_sesion,
        conectado,
        segunda,
        demo,
        need,
        res,
        asignado,
        excede,
        lista,
        uso,
        raro,
        resumen
      ] = salidas

      assert sin_sesion =~ "debe conectarse"
      assert conectado =~ "Usuario registrado y conectado"
      assert segunda =~ "ya hay una sesión activa"
      assert demo =~ "Datos de ejemplo cargados"
      assert need =~ "Necesidad N001 registrada"
      assert res =~ "Recurso R001 registrado"
      assert asignado =~ "Asignado a N001: 30 de R001"
      assert excede =~ "necesidad ya tiene cubierta"
      assert lista =~ "N001"
      assert uso =~ "Sintaxis: register_zone"
      assert raro =~ "comando desconocido"
      assert resumen =~ "agua: 20 litros"

      {_estado, salida} = Comandos.ejecutar("disconnect", estado)
      assert salida =~ "cerrada"
    end

    test "restricción por rol desde la consola" do
      {[_, salida], _} = correr(["connect pedro 1234 ciudadano", "register_zone z1 Z alto"])
      assert salida =~ "no tiene permiso"
    end

    test "help muestra solo lo permitido al rol" do
      {[_, ayuda], _} = correr(["connect pedro 1234 ciudadano", "help"])
      assert ayuda =~ "report_person"
      refute ayuda =~ "assign_resource"
    end
  end
end
