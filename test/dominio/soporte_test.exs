defmodule Emergencias.SoporteTest do
  use ExUnit.Case, async: true

  alias Emergencias.{Persistencia, Validacion}
  alias Emergencias.Dominio.Transiciones

  doctest Emergencias.Validacion
  doctest Emergencias.Dominio.Transiciones

  describe "Persistencia: codificación de líneas" do
    test "ida y vuelta conserva separadores, barras, saltos de línea y tildes" do
      campos = ["N001", "a|b", "ruta\\con\\barras", "línea 1\nlínea 2", "", "\\p literal"]
      linea = Persistencia.codificar_linea(campos)

      refute String.contains?(linea, "\n")
      assert length(String.split(linea, "|")) == length(campos)
      assert Persistencia.decodificar_linea(linea) == campos
    end

    test "convierte valores a texto" do
      assert Persistencia.codificar_linea([nil, :critica, 30]) == "|critica|30"
    end

    test "a_atomo nunca crea átomos nuevos" do
      assert Persistencia.a_atomo("critica", [:critica, :alta]) == :critica
      assert Persistencia.a_atomo("inventado", [:critica, :alta]) == nil
    end
  end

  describe "Validacion" do
    test "enteros no negativos y positivos" do
      assert Validacion.entero_no_negativo("0", :cantidad) == {:ok, 0}
      assert Validacion.entero_no_negativo("-5", :cantidad) == {:error, {:negativo, :cantidad}}

      assert Validacion.entero_no_negativo("diez", :cantidad) ==
               {:error, {:no_numerico, :cantidad}}

      assert Validacion.entero_positivo(0, :cantidad) == {:error, {:debe_ser_positivo, :cantidad}}
      assert Validacion.entero_positivo(" 12 ", :cantidad) == {:ok, 12}
    end

    test "opciones de catálogo sin importar tildes ni mayúsculas" do
      catalogo = %{"critica" => :critica}
      assert Validacion.opcion("CRÍTICA", catalogo, :prioridad) == {:ok, :critica}

      assert {:error, {:opcion_invalida, :prioridad, [:critica]}} =
               Validacion.opcion("x", catalogo, :prioridad)
    end

    test "identificadores sin espacios" do
      assert Validacion.identificador("centro_acopio-1", :codigo) == {:ok, "centro_acopio-1"}

      assert Validacion.identificador("con espacio", :codigo) ==
               {:error, {:identificador_invalido, :codigo}}
    end
  end

  describe "Transiciones" do
    test "transiciones válidas e inválidas de necesidades" do
      assert Transiciones.validar(:necesidad, :pendiente, :asignada) == :ok

      assert Transiciones.validar(:necesidad, :pendiente, :atendida) ==
               {:error, {:transicion_invalida, :pendiente, :atendida}}

      assert Transiciones.validar(:necesidad, :cancelada, :pendiente) ==
               {:error, {:ya_cerrado, :cancelada}}
    end

    test "estados terminales" do
      assert Transiciones.terminal?(:persona, :reunificada)
      assert Transiciones.terminal?(:mascota, :resuelta)
      refute Transiciones.terminal?(:mensaje, :entregado)
    end
  end
end
