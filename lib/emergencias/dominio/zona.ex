defmodule Emergencias.Dominio.Zona do
  @moduledoc """
  Estructura jerárquica de la emergencia: zona → sectores → puntos de atención.

  Todo el árbol se representa con un único tipo de nodo; `tipo` indica el nivel
  (`:zona`, `:sector` o `:punto`) y `hijos` es la lista de nodos descendientes.
  Las operaciones sobre el árbol son recursivas: el caso base es la lista vacía
  de hijos y el caso recursivo procesa el primer nodo y luego el resto.
  """

  alias Emergencias.{Persistencia, Validacion}

  defstruct [:codigo, :nombre, :tipo, :nivel, :categoria, personas: 0, hijos: []]

  @niveles %{
    "critico" => :critico,
    "critica" => :critico,
    "alto" => :alto,
    "alta" => :alto,
    "medio" => :medio,
    "media" => :medio,
    "bajo" => :bajo,
    "baja" => :bajo
  }

  # Qué tipo de hijo admite cada tipo de nodo.
  @hijo_permitido %{zona: :sector, sector: :punto, punto: nil}

  def niveles, do: [:critico, :alto, :medio, :bajo]
  def validar_nivel(texto), do: Validacion.opcion(texto, @niveles, :nivel)

  def peso_nivel(:critico), do: 4
  def peso_nivel(:alto), do: 3
  def peso_nivel(:medio), do: 2
  def peso_nivel(:bajo), do: 1
  def peso_nivel(_), do: 0

  @doc "Construye un nodo validando sus campos."
  def nuevo(tipo, codigo, nombre, nivel, personas, categoria \\ nil) do
    with {:ok, codigo} <- Validacion.identificador(codigo, :codigo),
         {:ok, nombre} <- Validacion.texto_requerido(nombre, :nombre),
         {:ok, nivel} <- Validacion.opcional(nivel, nil, &validar_nivel/1),
         {:ok, personas} <-
           Validacion.opcional(personas, 0, &Validacion.entero_no_negativo(&1, :personas)) do
      {:ok,
       %__MODULE__{
         codigo: codigo,
         nombre: nombre,
         tipo: tipo,
         nivel: nivel || (tipo != :punto && :medio) || nil,
         personas: personas,
         categoria: categoria && Validacion.normalizar(categoria)
       }}
    end
  end

  # ---------------------------------------------------------------------------
  # Funciones recursivas sobre el árbol
  # ---------------------------------------------------------------------------

  @doc """
  RECURSIVA. Búsqueda en profundidad de un nodo por código dentro de una lista de nodos.
  Caso base: lista vacía → `nil`. Si el primer nodo coincide se devuelve; si no,
  se busca primero en sus hijos y luego en los hermanos restantes.
  """
  def buscar([], _codigo), do: nil
  def buscar([%__MODULE__{codigo: codigo} = nodo | _resto], codigo), do: nodo
  def buscar([nodo | resto], codigo), do: buscar(nodo.hijos, codigo) || buscar(resto, codigo)

  @doc """
  RECURSIVA. Devuelve la ruta de códigos desde la raíz hasta el nodo buscado
  (por ejemplo `["centro", "sector_3", "punto_s3"]`), o `nil` si no existe.
  """
  def ruta([], _codigo), do: nil
  def ruta([%__MODULE__{codigo: codigo} | _resto], codigo), do: [codigo]

  def ruta([nodo | resto], codigo) do
    case ruta(nodo.hijos, codigo) do
      nil -> ruta(resto, codigo)
      camino -> [nodo.codigo | camino]
    end
  end

  @doc "Código de la zona raíz que contiene al nodo dado."
  def raiz(nodos, codigo) do
    case ruta(nodos, codigo) do
      nil -> nil
      [raiz | _] -> raiz
    end
  end

  @doc """
  RECURSIVA. Inserta `hijo` dentro del nodo `codigo_padre`. Recorre la lista de nodos;
  cuando encuentra al padre agrega el hijo, si no desciende por sus hijos.
  Devuelve `{:ok, nodos}` o `{:error, motivo}`.
  """
  def insertar(nodos, codigo_padre, hijo) do
    case insertar_en(nodos, codigo_padre, hijo) do
      {:ok, nuevos} -> {:ok, nuevos}
      :no_encontrado -> {:error, {:no_encontrado, codigo_padre}}
      {:error, _} = error -> error
    end
  end

  defp insertar_en([], _codigo_padre, _hijo), do: :no_encontrado

  defp insertar_en([%__MODULE__{codigo: codigo_padre} = padre | resto], codigo_padre, hijo) do
    if Map.fetch!(@hijo_permitido, padre.tipo) == hijo.tipo do
      {:ok, [%{padre | hijos: padre.hijos ++ [hijo]} | resto]}
    else
      {:error, {:jerarquia_invalida, padre.tipo, hijo.tipo}}
    end
  end

  defp insertar_en([nodo | resto], codigo_padre, hijo) do
    case insertar_en(nodo.hijos, codigo_padre, hijo) do
      {:ok, hijos} ->
        {:ok, [%{nodo | hijos: hijos} | resto]}

      :no_encontrado ->
        with {:ok, resto} <- insertar_en(resto, codigo_padre, hijo), do: {:ok, [nodo | resto]}

      error ->
        error
    end
  end

  @doc "RECURSIVA. Aplica `funcion` al nodo con el código dado y reconstruye el árbol."
  def actualizar([], _codigo, _funcion), do: :no_encontrado

  def actualizar([%__MODULE__{codigo: codigo} = nodo | resto], codigo, funcion),
    do: {:ok, [funcion.(nodo) | resto]}

  def actualizar([nodo | resto], codigo, funcion) do
    case actualizar(nodo.hijos, codigo, funcion) do
      {:ok, hijos} ->
        {:ok, [%{nodo | hijos: hijos} | resto]}

      :no_encontrado ->
        with {:ok, resto} <- actualizar(resto, codigo, funcion), do: {:ok, [nodo | resto]}
    end
  end

  @doc """
  RECURSIVA. Todos los códigos del subárbol (el propio nodo y sus descendientes).
  Se usa para saber qué necesidades, recursos y albergues pertenecen a una zona.
  """
  def codigos(%__MODULE__{codigo: codigo, hijos: hijos}), do: [codigo | codigos_lista(hijos)]

  defp codigos_lista([]), do: []
  defp codigos_lista([nodo | resto]), do: codigos(nodo) ++ codigos_lista(resto)

  @doc """
  RECURSIVA. Estadísticas acumuladas de un nodo y todo su subárbol.

  `contar` es una función `codigo -> mapa de contadores` (por ejemplo cuántas
  necesidades pendientes hay registradas directamente en ese código). El resultado
  conserva la jerarquía: cada nodo trae sus estadísticas `propias`, las `totales`
  (propias + las de todos sus descendientes) y la lista de `hijos` ya calculada.
  """
  def acumular(%__MODULE__{} = nodo, contar) do
    propias = Map.put(contar.(nodo.codigo), :personas_afectadas, nodo.personas)
    hijos = Enum.map(nodo.hijos, &acumular(&1, contar))
    totales = sumar_estadisticas([propias | Enum.map(hijos, & &1.totales)])

    %{
      codigo: nodo.codigo,
      nombre: nodo.nombre,
      tipo: nodo.tipo,
      nivel: nodo.nivel,
      propias: propias,
      totales: totales,
      hijos: hijos
    }
  end

  @doc "RECURSIVA. Suma, clave a clave, una lista de mapas de contadores."
  def sumar_estadisticas([]), do: %{}

  def sumar_estadisticas([mapa | resto]) do
    Map.merge(mapa, sumar_estadisticas(resto), fn _clave, a, b -> a + b end)
  end

  @doc """
  RECURSIVA. Aplana el árbol en preorden como `{profundidad, nodo}`.
  El preorden garantiza que un padre siempre aparece antes que sus hijos,
  lo que permite guardar y reconstruir el árbol línea a línea.
  """
  def aplanar(nodos, profundidad \\ 0)
  def aplanar([], _profundidad), do: []

  def aplanar([nodo | resto], profundidad) do
    [{profundidad, nodo} | aplanar(nodo.hijos, profundidad + 1)] ++ aplanar(resto, profundidad)
  end

  # ---------------------------------------------------------------------------
  # Persistencia: una línea por nodo con el código del padre
  # ---------------------------------------------------------------------------

  def a_filas(nodos), do: filas(nodos, nil)

  defp filas([], _padre), do: []

  defp filas([n | resto], padre) do
    [
      [n.codigo, n.nombre, n.tipo, n.nivel, n.personas, n.categoria, padre]
      | filas(n.hijos, n.codigo)
    ] ++
      filas(resto, padre)
  end

  @doc "Reconstruye el árbol insertando las filas en orden (los padres van primero)."
  def desde_filas(filas) do
    Enum.reduce(filas, [], fn [codigo, nombre, tipo, nivel, personas, categoria, padre], arbol ->
      nodo = %__MODULE__{
        codigo: codigo,
        nombre: nombre,
        tipo: Persistencia.a_atomo(tipo, [:zona, :sector, :punto]),
        nivel: Persistencia.a_atomo(nivel, niveles()),
        personas: Persistencia.a_entero(personas),
        categoria: Persistencia.a_texto_o_nil(categoria)
      }

      case padre do
        "" ->
          arbol ++ [nodo]

        _ ->
          case insertar(arbol, padre, nodo) do
            {:ok, nuevo} -> nuevo
            {:error, _} -> arbol
          end
      end
    end)
  end
end
