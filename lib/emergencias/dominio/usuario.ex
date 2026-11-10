defmodule Emergencias.Dominio.Usuario do
  @moduledoc """
  Usuario del sistema. La contraseña nunca se guarda en claro: se almacena
  `SHA-256(sal <> clave)` junto con una sal aleatoria.
  """

  alias Emergencias.{Persistencia, Validacion}

  defstruct [:username, :hash, :sal, :nombre_completo, :tipo, :zona, :creado_en]

  @tipos %{
    "ciudadano" => :ciudadano,
    "voluntario" => :voluntario,
    "coordinador" => :coordinador,
    "coordinadora" => :coordinador,
    "administrador" => :administrador,
    "administradora" => :administrador,
    "admin" => :administrador
  }

  def tipos, do: [:ciudadano, :voluntario, :coordinador, :administrador]

  def validar_tipo(texto), do: Validacion.opcion(texto, @tipos, :tipo_usuario)

  @doc "Crea un usuario validando cada campo antes de construir la estructura."
  def nuevo(username, clave, tipo, zona, nombre_completo) do
    with {:ok, username} <- validar_username(username),
         {:ok, clave} <- validar_clave(clave),
         {:ok, tipo} <- Validacion.opcional(tipo, :ciudadano, &validar_tipo/1),
         {:ok, zona} <- Validacion.opcional(zona, "general", &Validacion.identificador(&1, :zona)) do
      sal = :crypto.strong_rand_bytes(8) |> Base.encode16()

      {:ok,
       %__MODULE__{
         username: username,
         sal: sal,
         hash: calcular_hash(sal, clave),
         nombre_completo: nombre_o_defecto(nombre_completo, username),
         tipo: tipo,
         zona: zona,
         creado_en: Persistencia.ahora()
       }}
    end
  end

  def clave_valida?(%__MODULE__{hash: hash, sal: sal}, clave) when is_binary(clave) do
    calcular_hash(sal, clave) == hash
  end

  def clave_valida?(_usuario, _clave), do: false

  defp calcular_hash(sal, clave), do: :crypto.hash(:sha256, sal <> clave) |> Base.encode16()

  defp validar_username(valor) when is_binary(valor) do
    texto = String.trim(valor)

    if Regex.match?(~r/^[A-Za-z0-9_.\-]{3,30}$/, texto),
      do: {:ok, String.downcase(texto)},
      else: {:error, :usuario_invalido}
  end

  defp validar_username(_), do: {:error, :usuario_invalido}

  defp validar_clave(clave) when is_binary(clave) and byte_size(clave) >= 4, do: {:ok, clave}
  defp validar_clave(_), do: {:error, :clave_muy_corta}

  defp nombre_o_defecto(nombre, defecto) when is_binary(nombre) do
    case String.trim(nombre) do
      "" -> defecto
      texto -> texto
    end
  end

  defp nombre_o_defecto(_nombre, defecto), do: defecto

  # ---------------------------------------------------------------------------
  # Persistencia
  # ---------------------------------------------------------------------------

  def a_fila(u), do: [u.username, u.hash, u.sal, u.nombre_completo, u.tipo, u.zona, u.creado_en]

  def desde_fila([username, hash, sal, nombre, tipo, zona, creado]) do
    %__MODULE__{
      username: username,
      hash: hash,
      sal: sal,
      nombre_completo: nombre,
      tipo: Persistencia.a_atomo(tipo, tipos()),
      zona: zona,
      creado_en: Persistencia.a_fecha(creado)
    }
  end
end
