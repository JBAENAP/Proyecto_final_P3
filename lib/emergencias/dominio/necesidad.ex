defmodule Emergencias.Dominio.Necesidad do
  @moduledoc """
  Solicitud de ayuda asociada a una persona, familia, albergue o zona.

  La prioridad no es solo informativa: `ordenar/1` la usa para ordenar los listados
  y `despachar/3` para decidir a quién se le entregan primero los recursos.
  """

  alias Emergencias.{Persistencia, Validacion}
  alias Emergencias.Dominio.Transiciones

  defstruct [
    :id,
    :tipo,
    :descripcion,
    :cantidad,
    :zona,
    :prioridad,
    :responsable,
    :estado,
    :asociado_tipo,
    :asociado_ref,
    :creada_en,
    asignada: 0,
    asignaciones: []
  ]

  @tipos %{
    "agua" => :agua,
    "alimentos" => :alimentos,
    "alimento" => :alimentos,
    "medicamentos" => :medicamentos,
    "medicamento" => :medicamentos,
    "primeros_auxilios" => :primeros_auxilios,
    "refugio" => :refugio,
    "transporte" => :transporte,
    "rescate" => :rescate,
    "otra" => :otra,
    "otro" => :otra
  }

  @prioridades %{
    "critica" => :critica,
    "critico" => :critica,
    "alta" => :alta,
    "alto" => :alta,
    "media" => :media,
    "medio" => :media,
    "baja" => :baja,
    "bajo" => :baja
  }

  @asociaciones %{
    "zona" => :zona,
    "persona" => :persona,
    "familia" => :familia,
    "albergue" => :albergue
  }

  @estados_abiertos [:pendiente, :asignada, :en_atencion]

  def tipos, do: @tipos |> Map.values() |> Enum.uniq()
  def prioridades, do: [:critica, :alta, :media, :baja]
  def estados, do: Transiciones.estados(:necesidad)
  def estados_abiertos, do: @estados_abiertos

  def validar_tipo(texto), do: Validacion.opcion(texto, @tipos, :tipo_necesidad)
  def validar_prioridad(texto), do: Validacion.opcion(texto, @prioridades, :prioridad)

  def validar_estado(texto) do
    catalogo = Map.new(estados(), fn e -> {Atom.to_string(e), e} end)
    Validacion.opcion(texto, catalogo, :estado)
  end

  @doc """
  Interpreta la asociación `tipo:referencia` (por ejemplo `albergue:A01`).
  Sin asociación explícita la necesidad queda asociada a su zona.
  """
  def validar_asociacion(nil, zona), do: {:ok, {:zona, zona}}
  def validar_asociacion("", zona), do: {:ok, {:zona, zona}}

  def validar_asociacion(texto, _zona) do
    with [tipo, referencia] <- String.split(texto, ":", parts: 2),
         {:ok, tipo} <- Validacion.opcion(tipo, @asociaciones, :asociado_a),
         {:ok, referencia} <- Validacion.texto_requerido(referencia, :asociado_a) do
      {:ok, {tipo, referencia}}
    else
      {:error, _} = error -> error
      _ -> {:error, {:formato_invalido, :asociado_a, "tipo:referencia"}}
    end
  end

  def peso(:critica), do: 4
  def peso(:alta), do: 3
  def peso(:media), do: 2
  def peso(:baja), do: 1

  @doc "Construye una necesidad nueva en estado pendiente."
  def nueva(id, attrs) do
    with {:ok, tipo} <- validar_tipo(attrs[:tipo]),
         {:ok, cantidad} <- Validacion.entero_positivo(attrs[:cantidad], :cantidad),
         {:ok, prioridad} <- validar_prioridad(attrs[:prioridad]),
         {:ok, zona} <- Validacion.identificador(attrs[:zona] || "", :zona),
         {:ok, descripcion} <-
           Validacion.opcional(attrs[:descripcion], "", &{:ok, String.trim(&1)}),
         {:ok, {asociado_tipo, asociado_ref}} <- validar_asociacion(attrs[:asociado_a], zona) do
      {:ok,
       %__MODULE__{
         id: id,
         tipo: tipo,
         descripcion: descripcion,
         cantidad: cantidad,
         zona: zona,
         prioridad: prioridad,
         responsable: attrs[:responsable],
         estado: :pendiente,
         asociado_tipo: asociado_tipo,
         asociado_ref: asociado_ref,
         creada_en: Persistencia.ahora()
       }}
    end
  end

  def faltante(%__MODULE__{cantidad: cantidad, asignada: asignada}),
    do: max(cantidad - asignada, 0)

  def abierta?(%__MODULE__{estado: estado}), do: estado in @estados_abiertos

  @doc """
  Verifica, sin modificar nada, si se pueden asignar `cantidad` unidades.
  Una necesidad atendida o cancelada nunca vuelve a consumir recursos.
  """
  def puede_asignar(%__MODULE__{estado: estado}, _cantidad)
      when estado in [:atendida, :cancelada],
      do: {:error, {:ya_cerrado, estado}}

  def puede_asignar(%__MODULE__{} = necesidad, cantidad) do
    falta = faltante(necesidad)

    cond do
      falta == 0 -> {:error, :necesidad_cubierta}
      cantidad > falta -> {:error, {:excede_lo_requerido, falta}}
      true -> :ok
    end
  end

  @doc "Registra un plan de retiro `[{codigo_recurso, cantidad}]` en la necesidad."
  def registrar_asignacion(%__MODULE__{} = necesidad, plan) do
    total = plan |> Enum.map(fn {_codigo, cantidad} -> cantidad end) |> Enum.sum()
    estado = if necesidad.estado == :pendiente, do: :asignada, else: necesidad.estado

    %{
      necesidad
      | asignada: necesidad.asignada + total,
        asignaciones: necesidad.asignaciones ++ plan,
        estado: estado
    }
  end

  @doc "Cambia el estado respetando la máquina de transiciones."
  def cambiar_estado(%__MODULE__{} = necesidad, nuevo) do
    with :ok <- Transiciones.validar(:necesidad, necesidad.estado, nuevo) do
      {:ok, %{necesidad | estado: nuevo}}
    end
  end

  @doc "Ordena por prioridad (más crítica primero) y, a igual prioridad, por antigüedad."
  def ordenar(necesidades) do
    Enum.sort_by(necesidades, fn n ->
      {-peso(n.prioridad), NaiveDateTime.to_iso8601(n.creada_en), n.id}
    end)
  end

  @doc """
  Filtra por los criterios de un mapa (`zona`, `tipo`, `prioridad`, `estado`).
  Los valores ya deben venir validados.
  """
  def filtrar(necesidades, filtros) do
    Enum.filter(necesidades, fn n ->
      Enum.all?(filtros, fn
        {:zonas, codigos} -> n.zona in codigos
        {campo, valor} -> Map.get(n, campo) == valor
      end)
    end)
  end

  @doc """
  RECURSIVA. Despacho por prioridad.

  Recibe necesidades YA ordenadas por prioridad y una función `asignar` que intenta
  entregar recursos a una necesidad y retorna `{:ok, necesidad_actualizada, plan}`
  o `{:error, motivo}`. Recorre la lista: caso base lista vacía; en el caso recursivo
  atiende la primera y continúa con las demás, acumulando el resultado de cada una.
  Como se procesan en orden, las críticas consumen el inventario antes que las bajas.
  """
  def despachar([], _asignar, acumulado), do: Enum.reverse(acumulado)

  def despachar([necesidad | resto], asignar, acumulado) do
    resultado =
      case asignar.(necesidad) do
        {:ok, actualizada, plan} -> {:asignada, actualizada, plan}
        {:error, motivo} -> {:sin_asignar, necesidad, motivo}
      end

    despachar(resto, asignar, [resultado | acumulado])
  end

  # ---------------------------------------------------------------------------
  # Persistencia
  # ---------------------------------------------------------------------------

  def a_fila(n) do
    asignaciones = Enum.map(n.asignaciones, fn {codigo, cantidad} -> "#{codigo}:#{cantidad}" end)

    [
      n.id,
      n.tipo,
      n.descripcion,
      n.cantidad,
      n.asignada,
      n.zona,
      n.prioridad,
      n.responsable,
      n.estado,
      n.asociado_tipo,
      n.asociado_ref,
      n.creada_en,
      Persistencia.de_lista(asignaciones)
    ]
  end

  def desde_fila([
        id,
        tipo,
        desc,
        cant,
        asignada,
        zona,
        prio,
        resp,
        estado,
        a_tipo,
        a_ref,
        creada,
        asig
      ]) do
    asignaciones =
      asig
      |> Persistencia.a_lista()
      |> Enum.map(fn par ->
        [codigo, cantidad] = String.split(par, ":")
        {codigo, String.to_integer(cantidad)}
      end)

    %__MODULE__{
      id: id,
      tipo: Persistencia.a_atomo(tipo, tipos()),
      descripcion: desc,
      cantidad: Persistencia.a_entero(cant),
      asignada: Persistencia.a_entero(asignada),
      zona: zona,
      prioridad: Persistencia.a_atomo(prio, prioridades()),
      responsable: resp,
      estado: Persistencia.a_atomo(estado, estados()),
      asociado_tipo: Persistencia.a_atomo(a_tipo, [:zona, :persona, :familia, :albergue]),
      asociado_ref: a_ref,
      creada_en: Persistencia.a_fecha(creada),
      asignaciones: asignaciones
    }
  end
end
