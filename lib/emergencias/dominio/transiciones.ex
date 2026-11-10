defmodule Emergencias.Dominio.Transiciones do
  @moduledoc """
  Máquinas de estado del dominio.

  Cada máquina es un mapa `estado => MapSet de estados destino`. Se usa MapSet
  porque la única pregunta que se le hace es de pertenencia ("¿puedo pasar de A a B?").
  Un estado con MapSet vacío es terminal: el registro ya está cerrado y no puede
  volver a resolverse.
  """

  @maquinas %{
    necesidad: %{
      pendiente: MapSet.new([:asignada, :en_atencion, :cancelada]),
      asignada: MapSet.new([:en_atencion, :cancelada]),
      en_atencion: MapSet.new([:atendida, :cancelada]),
      atendida: MapSet.new(),
      cancelada: MapSet.new()
    },
    persona: %{
      sin_informacion: MapSet.new([:reportada, :localizada, :trasladada, :en_albergue]),
      reportada: MapSet.new([:localizada, :trasladada, :en_albergue, :reunificada]),
      localizada: MapSet.new([:trasladada, :en_albergue, :reunificada]),
      trasladada: MapSet.new([:localizada, :en_albergue, :reunificada]),
      en_albergue: MapSet.new([:trasladada, :localizada, :reunificada]),
      reunificada: MapSet.new()
    },
    mascota: %{
      activa: MapSet.new([:posible_coincidencia, :resuelta]),
      posible_coincidencia: MapSet.new([:activa, :resuelta]),
      resuelta: MapSet.new()
    },
    mensaje: %{
      pendiente: MapSet.new([:entregado]),
      entregado: MapSet.new([:pendiente])
    }
  }

  @doc "Estados posibles de una máquina."
  def estados(maquina), do: @maquinas |> Map.fetch!(maquina) |> Map.keys()

  def terminal?(maquina, estado) do
    @maquinas |> Map.fetch!(maquina) |> Map.get(estado, MapSet.new()) |> MapSet.size() == 0
  end

  @doc """
  Valida el paso de `desde` a `hacia`.

      iex> Emergencias.Dominio.Transiciones.validar(:necesidad, :atendida, :asignada)
      {:error, {:ya_cerrado, :atendida}}
  """
  def validar(maquina, desde, hacia) do
    destinos = @maquinas |> Map.fetch!(maquina) |> Map.get(desde, MapSet.new())

    cond do
      MapSet.member?(destinos, hacia) -> :ok
      MapSet.size(destinos) == 0 -> {:error, {:ya_cerrado, desde}}
      desde == hacia -> {:error, {:mismo_estado, desde}}
      true -> {:error, {:transicion_invalida, desde, hacia}}
    end
  end
end
