# Decisiones de diseño

## 1. Estructuras de datos y su justificación

| Estructura | Dónde | Por qué |
|---|---|---|
| **Structs** (mapas con forma fija) | `Dominio.*` | Documentan los campos de cada entidad y permiten pattern matching (`%Necesidad{estado: :atendida}`). |
| **Mapas** `%{id => struct}` | estado de todos los GenServers | Búsqueda por identificador en tiempo logarítmico y detección directa de identificadores repetidos (`Map.has_key?`). |
| **Árbol de structs anidados** (`%Zona{hijos: [...]}`) | `Dominio.Zona` | La jerarquía zona → sector → punto es naturalmente un árbol; se recorre con funciones recursivas. |
| **Listas** | historiales (movimientos, cambios de estado, bitácora), resultados ordenados | Orden de inserción; agregar al inicio es O(1) (`[nuevo \| historial]`). |
| **Tuplas** | `{:ok, valor}` / `{:error, motivo}`, cambios de estado `{fecha, desde, hacia, usuario, detalle}`, planes `{codigo, cantidad}` | Tamaño fijo y pattern matching; las tuplas de resultado evitan excepciones en situaciones esperadas. |
| **MapSet** | ocupantes de un albergue, destinos válidos de cada estado, permisos por rol, palabras de las características de una mascota | Lo único que se pregunta es pertenencia (`member?`) o se necesita unión/intersección (herencia de permisos, índice de Jaccard). Evita duplicados por construcción. |
| **Keyword lists** | opciones de `Inventario.retirar/3` (`desde:`, `parcial:`, `preferir:`) | Convención de Elixir para opciones opcionales. |

## 2. Funciones recursivas propias

| # | Función | Archivo | Caso base / caso recursivo |
|---|---|---|---|
| 1 | `Zona.buscar/2` | [zona.ex](../lib/emergencias/dominio/zona.ex) | `[]` → `nil`; si no coincide busca en los hijos y luego en los hermanos (DFS sobre zona → sectores → puntos). |
| 2 | `Zona.ruta/2` | zona.ex | `[]` → `nil`; arma el camino desde la raíz al nodo. |
| 3 | `Zona.insertar/3` (`insertar_en/3`) | zona.ex | `[]` → `:no_encontrado`; reconstruye el árbol inmutable con el hijo agregado. |
| 4 | `Zona.actualizar/3` | zona.ex | igual que insertar, aplicando una función al nodo. |
| 5 | `Zona.codigos/1` | zona.ex | todos los códigos del subárbol (`[codigo \| codigos(hijos)]`). |
| 6 | `Zona.acumular/2` | zona.ex | estadísticas acumuladas: propias + `acumular` de cada hijo (requisito recursivo sobre la jerarquía). |
| 7 | `Zona.sumar_estadisticas/1` | zona.ex | `[]` → `%{}`; suma clave a clave. |
| 8 | `Zona.aplanar/2` | zona.ex | recorrido en preorden con profundidad (para mostrar y persistir el árbol). |
| 9 | `Necesidad.despachar/3` | [necesidad.ex](../lib/emergencias/dominio/necesidad.ex) | `[]` → resultados; atiende la necesidad de mayor prioridad y continúa con el resto. |
| 10 | `Recurso.planificar_retiro/3` | [recurso.ex](../lib/emergencias/dominio/recurso.ex) | falta 0 → plan; sin candidatos → `:insuficiente`; toma lo posible del primero y sigue. |
| 11 | `Albergue.top/3` e `insertar_ordenado/2` | [albergue.ex](../lib/emergencias/dominio/albergue.ex) | ranking acotado de mayor ocupación por inserción ordenada. |
| 12 | `Parser.tokenizar/4` | [parser.ex](../lib/emergencias/cli/parser.ex) | tokenizador carácter a carácter con estado (normal / entre comillas). |
| 13 | `Persistencia.desescapar/2` | [persistencia.ex](../lib/emergencias/persistencia.ex) | `""` → texto; interpreta secuencias `\\`, `\p`, `\n`. |
| 14 | `Bitacora.ciclo/1` y `Consola.bucle/1` | bitacora.ex, consola.ex | ciclos de proceso / REPL que llevan el estado como argumento. |
| 15 | `Menu.bucle/2` y `Menu.pedir_campos/2` | [menu.ex](../lib/emergencias/cli/menu.ex) | `bucle`: cada vuelta muestra una pantalla, lee la opción y continúa (termina con `0` en el menú principal). `pedir_campos`: `[]` → valores; pide el primer campo y continúa con el resto. |

El enunciado pide al menos cuatro; las 1–8 cumplen además el requisito de usar la
estructura zona → sectores → puntos de atención en un algoritmo recursivo.

## 3. Concurrencia

* **Multiusuario distribuido**: cada usuario usa su propia terminal, que es un nodo
  Erlang (`clienteN@equipo`) en el mismo computador. Los clientes solo tienen la
  consola; todas las operaciones se ejecutan en el nodo `servidor` con `:erpc.call`.
  Así los usuarios trabajan de verdad en paralelo (VMs distintas) y el estado
  compartido vive en un único lugar.
* **Procesos independientes**: `Bitacora` (spawn + receive), una `Sesion` por usuario,
  tareas de `Task.Supervisor` para coincidencias, resumen y simulación.
* **GenServer**: siete servidores dueños del estado. Un GenServer atiende su mailbox de
  uno en uno, así que *leer-verificar-modificar* dentro de un `handle_call` es atómico.
* **Conflicto resuelto** (requisito obligatorio): `Inventario.retirar/3` verifica la
  existencia total y descuenta en el mismo `handle_call`. La asignación es *todo o nada*:
  con 50 litros y pedidos simultáneos de 30 y 25, uno se confirma y el otro recibe
  `{:error, {:inventario_insuficiente, 20}}`. Probado en
  `test/servidores/concurrencia_test.exs` con 100 tareas simultáneas y con el flujo exacto,
  y en `test/distribuido_test.exs` con dos terminales (nodos) pidiendo a la vez.
* **Sin bloqueos mutuos**: la única llamada entre servidores es `Necesidades → Inventario`
  (una sola dirección).
* **Sin doble cierre**: necesidades, personas, mascotas y mensajes validan la transición
  dentro de su GenServer; diez cierres simultáneos de la misma necesidad producen
  exactamente uno exitoso.
* **Paralelismo real**: `summary` lanza 7 consultas a la vez y `match_pets` compara cada
  reporte perdido en una tarea distinta.

## 4. Persistencia

Texto plano, una línea por registro y campos separados por `|` con escape de `|`, `\` y
saltos de línea. Las tablas se reescriben de forma atómica (archivo `.tmp` + `rename`)
para no dejar un archivo a medio escribir; los historiales solo agregan líneas. Cada
GenServer recarga su archivo en `init/1`, lo que también lo hace tolerante a reinicios.

## 5. Validaciones y manejo de errores

* Identificadores únicos (incluso entre nodos del árbol y albergues).
* Cantidades y capacidades no negativas; inventario y capacidad nunca se superan.
* Transiciones de estado según `Dominio.Transiciones`; estados terminales no se reabren.
* Toda entrada del usuario se valida (tipos, catálogos, existencia de zonas/albergues/personas)
  antes de modificar el estado.
* Las funciones de dominio retornan `{:ok, _}` / `{:error, motivo}`; la consola traduce
  cada motivo a un mensaje en español (`CLI.Formato.mensaje_error/1`).

## 6. Algoritmo de coincidencia de mascotas

Puntaje de 0 a 100 (`Dominio.Coincidencias`): especie 30 (obligatoria, si difiere el
total es 0), color 20 (Jaccard sobre raíces: "negra" ≈ "negro"), tamaño 15 (vecino 7),
zona 15 (misma zona raíz 8), nombre 10 (desconocido 5), características 10 (Jaccard de
palabras). Desde 60 puntos los reportes pasan a `posible_coincidencia`; `confirm_match`
cierra ambos como `resuelta`.

## 7. Datos de muestra y menú

* **Datos de muestra (`DatosIniciales`)**: se cargan solo si no hay zonas, para no duplicar
  personas, necesidades ni mensajes en cada arranque. Se registran llamando a la fachada con
  el usuario del rol correspondiente (ciudadano, voluntario o coordinador), así que pasan por
  los mismos permisos, validaciones, persistencia y bitácora que una operación real. Las zonas
  son las 10 comunas de Armenia (Quindío) y el corregimiento El Caimo; el resto es ficticio.
  El flujo del enunciado (`demo/flujo_ejemplo.txt`) se ejecuta en una carpeta temporal vacía
  porque depende de identificadores fijos (`N001`, `R001`).
* **Menú numerado (`CLI.Menu`)**: cada opción se describe como datos (comando + lista de campos
  a pedir) y al final se convierte en la misma línea de comando que se escribiría a mano
  (`construir_linea/2`). Así el menú no duplica lógica: reutiliza el parser, los permisos, la
  validación y el formato del modo comandos. Solo se muestran las opciones que el rol permite.
* **Conexión**: el menú consulta `usuario_registrado?/1` antes de pedir datos; a un usuario
  existente solo se le pide la contraseña. La validación de la contraseña sigue ocurriendo en
  el servidor (`Usuarios.conectar/5`).
