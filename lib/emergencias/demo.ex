defmodule Emergencias.Demo do
  @moduledoc """
  Datos de ejemplo para la sustentación: zonas, sectores, puntos de atención y
  albergues que usa el flujo de ejemplo del enunciado (`centro`, `zona_norte`,
  `centro_acopio_1`, `albergue_2`, `A01`...). Es idempotente: lo que ya existe se omite.
  """

  alias Emergencias.Servidores.{Albergues, Zonas}

  @zonas [
    {"centro", "Zona Centro", "critico", 1200},
    {"zona_norte", "Zona Norte", "alto", 800}
  ]

  @sectores [
    {"centro", "sector_1", "Sector 1", "alto", 400},
    {"centro", "sector_3", "Sector 3", "critico", 500},
    {"zona_norte", "norte_1", "Norte 1", "medio", 300}
  ]

  @puntos [
    {"sector_1", "centro_acopio_1", "Centro de Acopio 1", "acopio"},
    {"sector_3", "punto_s3", "Punto de atención sector 3", "atencion"},
    {"norte_1", "centro_acopio_2", "Centro de Acopio 2", "acopio"}
  ]

  @albergues [
    %{codigo: "A01", nombre: "Albergue Norte", zona: "zona_norte", capacidad: 150},
    %{codigo: "albergue_2", nombre: "Albergue Centro", zona: "centro", capacidad: 80}
  ]

  def cargar(_actor) do
    creados =
      Enum.map(@zonas, fn {c, n, nivel, p} -> {c, Zonas.registrar_zona(c, n, nivel, p)} end) ++
        Enum.map(@sectores, fn {z, c, n, nivel, p} ->
          {c, Zonas.registrar_sector(z, c, n, nivel, p)}
        end) ++
        Enum.map(@puntos, fn {s, c, n, cat} -> {c, Zonas.registrar_punto(s, c, n, cat)} end) ++
        Enum.map(@albergues, fn attrs -> {attrs.codigo, Albergues.registrar(attrs)} end)

    {:ok, for({codigo, {:ok, _}} <- creados, do: codigo)}
  end
end
