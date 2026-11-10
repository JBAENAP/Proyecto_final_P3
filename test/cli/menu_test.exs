defmodule Emergencias.CLI.MenuTest do
  use Emergencias.CasoSistema, async: false

  import ExUnit.CaptureIO

  alias Emergencias.CLI.Menu

  doctest Emergencias.CLI.Menu

  # Ejecuta el menú escribiendo las respuestas dadas, una por línea.
  defp usar_menu(respuestas) do
    capture_io(Enum.join(respuestas, "\n") <> "\n", fn -> Menu.iniciar() end)
  end

  describe "construir_linea/2" do
    test "omite opcionales al final y conserva la posición de los intermedios" do
      valores = [
        {:arg, "1001"},
        {:arg, "Ana Ruiz"},
        {:arg, "centro"},
        {:arg, "localizada"},
        {:arg, nil},
        {:arg, "ruiz"}
      ]

      assert Menu.construir_linea("report_person", valores) ==
               ~s(report_person 1001 "Ana Ruiz" centro localizada "" ruiz)

      assert Menu.construir_linea("availability", [{:arg, "agua"}, {:arg, nil}]) ==
               "availability agua"
    end

    test "los filtros se convierten en clave=valor y se omiten si no se responden" do
      valores = [
        {:opcion, "zona", "centro"},
        {:opcion, "tipo", nil},
        {:opcion, "prioridad", "critica"}
      ]

      assert Menu.construir_linea("list_needs", valores) ==
               "list_needs zona=centro prioridad=critica"
    end

    test "cita textos con espacios o '=' y reemplaza comillas" do
      assert Menu.construir_linea("x", [{:arg, ~s(dijo "hola")}, {:arg, "a=b"}]) ==
               ~s(x "dijo 'hola'" "a=b")
    end
  end

  test "sin sesión solo se ofrece conectarse, escribir comandos o salir" do
    salida = usar_menu(["0"])
    assert salida =~ "1. Conectarse o registrarse"
    assert salida =~ "2. Escribir un comando manualmente"
    assert salida =~ "0. Salir"
  end

  test "flujo completo por números: conectarse, cargar demo, registrar necesidad y listarla" do
    salida =
      usar_menu([
        # 1. Conectarse: usuario, clave, tipo 3 (coordinador), zona, nombre
        "1",
        "laura",
        "1234",
        "3",
        "centro",
        "Laura Gómez",
        "",
        # Resumen y reportes (sección 7) -> 5. Cargar datos de ejemplo
        "7",
        "5",
        "",
        "0",
        # Necesidades (sección 2) -> 1. Registrar: tipo 1 (agua), 30, prioridad 1 (crítica), zona, descripción, sin asociación
        "2",
        "1",
        "1",
        "30",
        "1",
        "centro",
        "Punto de atención sector 3",
        "",
        "",
        # 2. Listar necesidades filtrando solo por prioridad 1 (crítica)
        "2",
        "",
        "",
        "1",
        "",
        "",
        "0",
        # 0 en el principal = desconectarse; 0 otra vez = salir
        "0",
        "0"
      ])

    assert salida =~ "OK: Usuario registrado y conectado: Laura Gómez"
    assert salida =~ "Datos de ejemplo cargados"
    assert salida =~ ~s(> register_need agua 30 critica centro "Punto de atención sector 3")
    assert salida =~ "Necesidad N001 registrada"
    assert salida =~ "> list_needs prioridad=critica"
    assert salida =~ "N001 | critica"
    assert salida =~ "Sesión de laura cerrada"
  end

  test "el menú solo muestra las opciones permitidas al rol" do
    salida =
      usar_menu([
        "1",
        "pedro",
        "1234",
        "1",
        "",
        "",
        "",
        # 1. Zonas y sectores, volver; 2. Necesidades, volver
        "1",
        "0",
        "2",
        "0",
        "0",
        "0"
      ])

    # Un ciudadano consulta zonas y registra necesidades, pero no registra zonas,
    # no asigna recursos y no ve la sección de resumen.
    assert salida =~ "Ver árbol de zonas"
    assert salida =~ "Registrar necesidad"
    refute salida =~ "Registrar zona"
    refute salida =~ "Asignar recurso a una necesidad"
    refute salida =~ "Resumen y reportes"
  end

  test "opción inválida, dato obligatorio vacío y cancelar" do
    salida =
      usar_menu([
        "9",
        "1",
        "",
        "cancelar",
        "0"
      ])

    assert salida =~ "opción no válida"
    assert salida =~ "este dato es obligatorio"
    assert salida =~ "Operación cancelada."
  end

  test "elegir un número fuera de la lista vuelve a preguntar" do
    salida =
      usar_menu([
        "1",
        "ana",
        "1234",
        "7",
        "4",
        "",
        "",
        "",
        "0",
        "0"
      ])

    assert salida =~ "elija un número de la lista"
    assert salida =~ "administrador"
  end

  test "un usuario registrado solo ingresa su contraseña" do
    {:ok, _, :registrado} =
      Emergencias.Servidores.Usuarios.conectar(
        "laura",
        "1234",
        "coordinador",
        "centro",
        "Laura Gómez"
      )

    salida = usar_menu(["1", "Laura", "1234", "", "0", "0"])

    assert salida =~ "Usuario 'Laura' registrado. Ingrese su contraseña."
    assert salida =~ "Bienvenido de nuevo: Laura Gómez (laura) - coordinador"
    refute salida =~ "Tipo de usuario"
    refute salida =~ "Zona principal"
  end

  test "un usuario registrado con contraseña incorrecta no entra" do
    {:ok, _, :registrado} = Emergencias.Servidores.Usuarios.conectar("laura", "1234")
    salida = usar_menu(["1", "laura", "mala", "", "0"])
    assert salida =~ "ERROR: contraseña incorrecta"
    assert salida =~ "[sin conectar]"
  end

  test "un usuario nuevo recibe el formulario de registro" do
    salida = usar_menu(["1", "nuevo", "abcd", "2", "zona_norte", "Ana Nueva", "", "0", "0"])
    assert salida =~ "El usuario 'nuevo' no existe: se creará una cuenta nueva."
    assert salida =~ "Tipo de usuario"

    assert salida =~
             "Usuario registrado y conectado: Ana Nueva (nuevo) - voluntario - zona zona_norte"

    assert Emergencias.usuario_registrado?("NUEVO")
  end

  test "modo comandos dentro del menú" do
    salida = usar_menu(["2", "connect ana 1234 administrador", "whoami", "menu", "0", "0"])
    assert salida =~ "Modo comandos"
    assert salida =~ "ana (ana) - administrador"
  end
end
