defmodule Emergencias.MixProject do
  use Mix.Project

  def project do
    [
      app: :emergencias,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # :crypto se usa para el hash de contraseñas.
  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {Emergencias.Application, []}
    ]
  end

  defp deps do
    []
  end
end
