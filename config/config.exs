import Config

# Carpeta donde se guardan los archivos de texto plano (relativa a la raíz del proyecto).
config :emergencias,
  directorio_datos: "datos",
  # Cantidad mínima por debajo de la cual un recurso se considera crítico.
  umbral_critico: 10,
  # Puntaje mínimo (0-100) para considerar dos reportes de mascotas como posible coincidencia.
  umbral_coincidencia: 60

if config_env() == :test do
  config :emergencias, directorio_datos: Path.join(System.tmp_dir!(), "emergencias_test")
  config :logger, level: :warning
end
