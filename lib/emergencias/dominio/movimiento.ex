defmodule Emergencias.Dominio.Movimiento do
  @moduledoc """
  Movimiento de inventario. El historial es de solo inserción: nunca se modifica
  un movimiento ya registrado, así se puede reconstruir cualquier saldo.
  """

  alias Emergencias.Persistencia

  defstruct [:fecha, :tipo, :codigo, :cantidad, :saldo, :referencia, :usuario]

  @tipos [
    :registro,
    :entrada,
    :salida,
    :asignacion,
    :transferencia_salida,
    :transferencia_entrada
  ]

  def tipos, do: @tipos

  def nuevo(tipo, codigo, cantidad, saldo, referencia, usuario) when tipo in @tipos do
    %__MODULE__{
      fecha: Persistencia.ahora(),
      tipo: tipo,
      codigo: codigo,
      cantidad: cantidad,
      saldo: saldo,
      referencia: referencia,
      usuario: usuario
    }
  end

  def a_fila(m), do: [m.fecha, m.tipo, m.codigo, m.cantidad, m.saldo, m.referencia, m.usuario]

  def desde_fila([fecha, tipo, codigo, cantidad, saldo, referencia, usuario]) do
    %__MODULE__{
      fecha: Persistencia.a_fecha(fecha),
      tipo: Persistencia.a_atomo(tipo, @tipos),
      codigo: codigo,
      cantidad: Persistencia.a_entero(cantidad),
      saldo: Persistencia.a_entero(saldo),
      referencia: referencia,
      usuario: usuario
    }
  end
end
