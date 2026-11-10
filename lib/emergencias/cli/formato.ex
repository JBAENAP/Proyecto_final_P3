defmodule Emergencias.CLI.Formato do
  @moduledoc "Presentación en texto: tablas, fechas, etiquetas y mensajes de error en español."

  @doc """
  Tabla de texto con columnas alineadas.

      ID   | TIPO
      -----+-----
      N001 | agua
  """
  def tabla(_encabezados, []), do: "(sin resultados)"

  def tabla(encabezados, filas) do
    filas = Enum.map(filas, fn fila -> Enum.map(fila, &celda/1) end)

    anchos =
      [encabezados | filas]
      |> Enum.zip_with(& &1)
      |> Enum.map(fn columna -> columna |> Enum.map(&String.length/1) |> Enum.max() end)

    linea = fn fila ->
      fila
      |> Enum.zip(anchos)
      |> Enum.map(fn {texto, ancho} -> String.pad_trailing(texto, ancho) end)
      |> Enum.join(" | ")
    end

    separador = anchos |> Enum.map(&String.duplicate("-", &1)) |> Enum.join("-+-")
    Enum.join([linea.(encabezados), separador | Enum.map(filas, linea)], "\n")
  end

  def celda(nil), do: "-"
  def celda(valor) when is_atom(valor), do: etiqueta(valor)
  def celda(%NaiveDateTime{} = fecha), do: fecha(fecha)
  def celda(valor) when is_binary(valor), do: valor
  def celda(valor), do: to_string(valor)

  def etiqueta(nil), do: "-"

  def etiqueta(atomo) when is_atom(atomo),
    do: atomo |> Atom.to_string() |> String.replace("_", " ")

  def etiqueta(otro), do: to_string(otro)

  def fecha(nil), do: "-"
  def fecha(%NaiveDateTime{} = f), do: Calendar.strftime(f, "%Y-%m-%d %H:%M")

  def titulo(texto), do: "== #{texto} =="

  def ok(texto), do: "OK: " <> texto

  @doc "Mapa de contadores como `clave: valor, clave: valor`."
  def conteos(mapa) when map_size(mapa) == 0, do: "ninguno"

  def conteos(mapa) do
    mapa
    |> Enum.sort()
    |> Enum.map(fn {clave, valor} -> "#{etiqueta(clave)}: #{valor}" end)
    |> Enum.join(", ")
  end

  # ---------------------------------------------------------------------------
  # Errores
  # ---------------------------------------------------------------------------

  def error(motivo), do: "ERROR: " <> mensaje_error(motivo)

  def mensaje_error({:error, motivo}), do: mensaje_error(motivo)
  def mensaje_error({:uso, sintaxis}), do: "uso incorrecto. Sintaxis: #{sintaxis}"
  def mensaje_error({:comando_desconocido, c}), do: "comando desconocido '#{c}'. Escriba help"

  def mensaje_error(:no_conectado),
    do: "debe conectarse primero: connect usuario clave [tipo] [zona]"

  def mensaje_error(:ya_conectado), do: "ese usuario ya tiene una sesión abierta"

  def mensaje_error(:sesion_activa),
    do: "ya hay una sesión activa en esta consola; use disconnect"

  def mensaje_error(:sesion_perdida),
    do: "la sesión se cerró (¿se reinició el servidor?); vuelva a conectarse"

  def mensaje_error({:servidor_no_disponible, _motivo}),
    do: "no hay conexión con el servidor; verifique que la terminal del servidor siga abierta"

  def mensaje_error({:fallo_remoto, motivo}),
    do: "el servidor no pudo completar la operación (#{inspect(motivo)})"

  def mensaje_error(:clave_incorrecta), do: "contraseña incorrecta"

  def mensaje_error(:usuario_invalido),
    do: "nombre de usuario inválido (3-30 letras, números, . _ -)"

  def mensaje_error(:clave_muy_corta), do: "la contraseña debe tener al menos 4 caracteres"
  def mensaje_error(:comillas_sin_cerrar), do: "hay comillas sin cerrar"

  def mensaje_error({:sin_permiso, accion, rol}),
    do: "un usuario #{etiqueta(rol)} no tiene permiso para '#{accion}'"

  def mensaje_error({:no_encontrado, id}), do: "no existe '#{id}'"
  def mensaje_error({:id_duplicado, id}), do: "el identificador '#{id}' ya existe"
  def mensaje_error({:negativo, campo}), do: "#{etiqueta(campo)} no puede ser negativo"
  def mensaje_error({:no_numerico, campo}), do: "#{etiqueta(campo)} debe ser un número entero"
  def mensaje_error({:debe_ser_positivo, campo}), do: "#{etiqueta(campo)} debe ser mayor que cero"
  def mensaje_error({:requerido, campo}), do: "#{etiqueta(campo)} es obligatorio"
  def mensaje_error({:fuera_de_rango, campo}), do: "#{etiqueta(campo)} está fuera de rango"

  def mensaje_error({:identificador_invalido, campo}),
    do: "#{etiqueta(campo)} solo admite letras, números, _ y - (sin espacios)"

  def mensaje_error({:opcion_invalida, campo, opciones}),
    do:
      "valor inválido para #{etiqueta(campo)}. Opciones: #{opciones |> Enum.map(&etiqueta/1) |> Enum.join(", ")}"

  def mensaje_error({:formato_invalido, campo, ejemplo}),
    do: "formato inválido para #{etiqueta(campo)}; se espera #{ejemplo}"

  def mensaje_error({:filtro_desconocido, clave, validos}),
    do: "filtro desconocido '#{clave}'. Válidos: #{Enum.join(validos, ", ")}"

  def mensaje_error({:inventario_insuficiente, disponible}),
    do: "inventario insuficiente: solo hay #{disponible} unidades disponibles; no se asignó nada"

  def mensaje_error({:sin_recursos_de_tipo, tipo}),
    do: "no hay recursos registrados de tipo '#{tipo}'"

  def mensaje_error({:tipo_no_coincide, codigo, tipo}),
    do: "el recurso #{codigo} no es de tipo '#{tipo}'"

  def mensaje_error({:excede_lo_requerido, faltante}),
    do: "la cantidad supera lo que falta por cubrir de la necesidad (#{faltante})"

  def mensaje_error(:necesidad_cubierta),
    do: "la necesidad ya tiene cubierta toda la cantidad requerida"

  def mensaje_error({:ya_cerrado, estado}),
    do:
      "el registro ya está cerrado (#{etiqueta(estado)}) y no puede resolverse ni modificarse de nuevo"

  def mensaje_error({:mismo_estado, estado}),
    do: "el registro ya está en estado #{etiqueta(estado)}"

  def mensaje_error({:transicion_invalida, desde, hacia}),
    do: "no se puede pasar de #{etiqueta(desde)} a #{etiqueta(hacia)}"

  def mensaje_error({:capacidad_superada, capacidad}),
    do: "se superaría la capacidad máxima del albergue (#{capacidad})"

  def mensaje_error({:ya_esta_en_albergue, doc}),
    do: "la persona #{doc} ya está registrada en este albergue"

  def mensaje_error({:no_esta_en_albergue, doc}),
    do: "la persona #{doc} no está registrada en este albergue"

  def mensaje_error({:ya_esta_en_otro_albergue, codigo}),
    do: "la persona ya está registrada en el albergue #{codigo}; registre primero su salida"

  def mensaje_error({:zona_no_registrada, zona}),
    do:
      "el lugar '#{zona}' no está registrado (use register_zone / register_sector / register_point o load_demo)"

  def mensaje_error({:ubicacion_no_registrada, ubicacion}),
    do:
      "la ubicación '#{ubicacion}' no es un punto de atención, sector, zona ni albergue registrado"

  def mensaje_error({:jerarquia_invalida, padre, hijo}),
    do: "un #{etiqueta(padre)} no puede contener un #{etiqueta(hijo)} (zona → sector → punto)"

  def mensaje_error({:origen_incorrecto, real}),
    do: "el recurso no está en ese origen; está en #{real}"

  def mensaje_error(:origen_igual_destino), do: "el origen y el destino son el mismo"

  def mensaje_error(:mismo_tipo_de_reporte),
    do: "debe confirmar un reporte perdido con uno encontrado"

  def mensaje_error(:especies_distintas), do: "los reportes son de especies distintas"
  def mensaje_error(texto) when is_binary(texto), do: texto
  def mensaje_error(otro), do: inspect(otro)
end
