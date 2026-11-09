# Sistema Distribuido de Coordinación y Gestión de Emergencias

Proyecto final de Programación III (Universidad del Quindío), escrito en Elixir.
Simula una plataforma multiusuario para coordinar la atención después de un terremoto:
usuarios por rol, zonas → sectores → puntos de atención, necesidades con prioridad,
inventario de recursos, comunicación entre familiares, mascotas perdidas/encontradas y
albergues. Usa procesos, GenServer, Supervisor, DynamicSupervisor y persistencia en
archivos de texto plano.

> La interfaz web queda para una etapa posterior. Toda la lógica está expuesta en el
> módulo `Emergencias` (fachada), que la web podrá usar igual que hoy la usa la consola.

## Requisitos

* Elixir 1.15 o superior (probado con Elixir 1.20 / OTP 29). No hay dependencias externas.

## Uso multiusuario: una terminal por usuario (nodos Erlang)

Todo corre en un solo computador. Cada terminal es un nodo Erlang distinto:

| Terminal | Comando (en la carpeta `emergencias`) | Qué es |
|---|---|---|
| 1 | `servidor.bat` | Nodo `servidor@<equipo>`: GenServers, supervisores y archivos `datos/`. Muestra en vivo quién se conecta y qué hace. |
| 2, 3, 4… | `cliente.bat` | Nodo `cliente1`, `cliente2`…: la consola de un usuario. Cada comando se ejecuta en el servidor. |

Primero el servidor, luego tantos clientes como usuarios se quieran simular. En
PowerShell se ejecutan como `.\servidor.bat` y `.\cliente.bat`. Equivalentes sin los
`.bat`:

```bash
elixir --sname servidor --cookie emergencias -S mix servidor   # terminal del servidor
mix cliente                                                    # cada terminal de usuario
```

* Todos los usuarios ven el mismo estado (lo que registra uno, lo consulta otro).
* Si dos terminales piden el mismo recurso a la vez, el servidor solo confirma lo que
  alcanza en el inventario.
* Si se cierra una terminal, su sesión se cierra sola en el servidor.
* El servidor se detiene con Ctrl+C (y luego `a` + Enter).

## Otros modos

```bash
mix consola                          # todo en una sola VM (sin servidor aparte)
mix consola demo/flujo_ejemplo.txt   # ejecuta el flujo de ejemplo del enunciado
mix test                             # pruebas (incluye pruebas con nodos reales)
```

En Windows, si las tildes se ven mal en la terminal, ejecute `chcp 65001` antes (los
`.bat` ya lo hacen).

## Datos de muestra (Armenia, Quindío)

La primera vez que se inicia el servidor (o `mix consola`) sin zonas registradas se cargan
datos de muestra (`lib/emergencias/datos_iniciales.ex`):

| Usuario | Tipo | Contraseña |
|---|---|---|
| `pedro` | ciudadano | `0000` |
| `andres` | voluntario | `0000` |
| `laura` | coordinador | `0000` |
| `sofia` | administrador | `0000` |

* **Zonas:** las 10 comunas de Armenia (`comuna_1` Centenario … `comuna_10` Quimbaya) y el
  corregimiento `el_caimo`, cada una con sectores y puntos de atención/acopio.
* **Albergues:** `AL01`–`AL05`. **Recursos:** `R001`–`R013` (agua, mercados, medicamentos,
  botiquines, cobijas, carpas…; algunos por debajo del umbral crítico).
* **Personas, mensajes, necesidades y mascotas:** con distintos estados (necesidades pendientes,
  asignada, atendida y cancelada; mascotas que coinciden al ejecutar `match_pets`).

Los nombres de las comunas son reales; sectores, cifras, personas y demás datos son ficticios.
Para volver a empezar desde los datos de muestra: detener el servidor, borrar los `.txt` de
`datos/` y volver a iniciarlo.

`load_demo` agrega además las zonas `centro` y `zona_norte`, sus sectores y puntos
(`centro_acopio_1`, `punto_s3`, `centro_acopio_2`) y los albergues `A01` y `albergue_2`, que
son los que usa el ejemplo del enunciado. `mix consola demo/flujo_ejemplo.txt` ejecuta ese
ejemplo en una carpeta temporal vacía, sin tocar `datos/`.

## Comandos

| Área | Comandos |
|---|---|
| Sesión | `connect usuario clave [tipo] [zona] ["Nombre"]`, `disconnect`, `whoami`, `activity [usuario]`, `list_users`, `set_role usuario tipo` |
| Zonas | `register_zone`, `register_sector`, `register_point`, `update_zone`, `list_zones`, `zone_status`, `zone_stats` |
| Necesidades | `register_need tipo cantidad prioridad zona "desc" [para=albergue:A01]`, `list_needs [zona= tipo= prioridad= estado=]`, `pending_needs`, `assign_resource N001 agua 20 [desde=R001]`, `attend_need`, `close_need`, `cancel_need`, `dispatch_needs` |
| Recursos | `register_resource R001 agua 200 litros centro_acopio_1 [categoria]`, `list_resources`, `resource_in`, `resource_out`, `availability tipo [zona]`, `transfer_resource R001 origen destino 30`, `resource_history`, `critical_resources` |
| Familiares | `report_person doc "nombre" zona estado [edad] [familia]`, `update_person`, `find_person`, `search_persons`, `person_history`, `send_family_message doc "texto"`, `list_family_messages doc`, `mark_message` |
| Mascotas | `report_pet lost\|found especie "nombre" color tamaño zona contacto ["características"]`, `list_pets`, `match_pets`, `confirm_match PET001 PET002` |
| Albergues | `register_shelter A01 "Albergue Norte" zona_norte 150`, `check_shelter`, `register_entry`, `register_exit`, `list_shelters`, `shelters_available`, `shelter_report` |
| General | `summary`, `simulate_conflict ubicacion [stock] [30,25]`, `load_demo`, `help [comando]`, `exit` |

`help` muestra solo los comandos permitidos al rol conectado
(ciudadano ⊂ voluntario ⊂ coordinador ⊂ administrador).

## Documentación

* [Arquitectura de módulos](docs/arquitectura.md)
* [Modelo de datos](docs/modelo_datos.md)
* [Diagramas de secuencia](docs/secuencia.md)
* [Árbol de supervisión OTP](docs/arbol_otp.md)
* [Estructura del proyecto](docs/estructura.md)
* [Decisiones de diseño: estructuras, recursión, concurrencia, persistencia](docs/decisiones.md)

Los diagramas están en Mermaid; GitHub y VS Code los muestran directamente y se pueden
exportar a imagen desde <https://mermaid.live> para el documento de entrega.

## Lista de verificación del enunciado

| Requisito | Dónde |
|---|---|
| Gestiona usuarios | `Servidores.Usuarios`, `Sesiones.*`, `Permisos`, `Bitacora` |
| Gestiona zonas y sectores | `Dominio.Zona`, `Servidores.Zonas` |
| Gestiona necesidades | `Dominio.Necesidad`, `Servidores.Necesidades` |
| Gestiona recursos | `Dominio.Recurso`, `Dominio.Movimiento`, `Servidores.Inventario` |
| Comunicación entre familiares | `Dominio.Persona`, `Dominio.Mensaje`, `Servidores.Familias` |
| Mascotas perdidas y encontradas | `Dominio.Mascota`, `Dominio.Coincidencias`, `Servidores.Mascotas` |
| Albergues | `Dominio.Albergue`, `Servidores.Albergues` |
| Estructuras de datos justificadas | [decisiones.md §1](docs/decisiones.md) |
| ≥ 4 funciones recursivas propias | 14 listadas en [decisiones.md §2](docs/decisiones.md) |
| Procesos concurrentes | `Bitacora`, `Sesion`, tareas en `Emergencias.Tareas`, un nodo Erlang por terminal |
| GenServer | 7 servidores + `Sesion` |
| Supervisor y DynamicSupervisor | `Application`, `Servidores.Supervisor`, `Sesiones.SupervisorSesiones` |
| Conflicto concurrente resuelto | dos terminales `cliente.bat` a la vez, `simulate_conflict`, `test/servidores/concurrencia_test.exs`, `test/distribuido_test.exs` |
| Persistencia | `Persistencia`, carpeta `datos/` |
| Pruebas | `mix test` (101 pruebas, 4 con nodos reales) |
| Diagramas | carpeta `docs/` |

## Equipo

| Nombre completo | Código | Correo |
|---|---|---|
|  |  |  |
