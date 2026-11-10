# 3. Estructura del proyecto

```
emergencias/
├── servidor.bat                     # terminal del servidor (nodo servidor@equipo)
├── cliente.bat                      # terminal de un usuario (nodo clienteN@equipo)
├── mix.exs                          # proyecto Mix (app :emergencias, sin dependencias externas)
├── config/config.exs                # carpeta de datos, umbral crítico, umbral de coincidencias
├── datos/                           # persistencia: un .txt por entidad (los escribe solo el servidor)
│                                    #   usuarios, zonas, recursos, movimientos, necesidades, personas,
│                                    #   historial_personas, mensajes, mascotas, albergues, actividad
├── demo/flujo_ejemplo.txt           # flujo de ejemplo del enunciado (mix consola demo/flujo_ejemplo.txt,
│                                    #   se ejecuta en una carpeta temporal vacía)
├── docs/                            # diagramas (Mermaid) y justificación de diseño
│   └── img/                         # diagramas exportados a PNG para el documento de entrega
├── lib/
│   ├── emergencias.ex               # FACHADA: API pública (CLI hoy, web en el futuro)
│   ├── emergencias/
│   │   ├── application.ex           # árbol de supervisión raíz
│   │   ├── bitacora.ex              # proceso independiente (spawn + receive) de actividad
│   │   ├── distribucion.ex          # arranque de nodos servidor / clienteN, epmd, cookie
│   │   ├── permisos.ex              # rol → MapSet de acciones permitidas
│   │   ├── persistencia.ex          # texto plano: leer, guardar (atómico), agregar
│   │   ├── validacion.ex            # validaciones puras con tuplas de resultado
│   │   ├── datos_iniciales.ex       # datos de muestra de Armenia + usuarios (clave 0000)
│   │   ├── demo.ex                  # datos del ejemplo del enunciado (load_demo)
│   │   ├── simulacion.ex            # demostración del conflicto concurrente
│   │   ├── dominio/                 # structs + funciones puras
│   │   │   ├── usuario.ex  zona.ex  necesidad.ex  recurso.ex  movimiento.ex
│   │   │   ├── persona.ex  mensaje.ex  mascota.ex  coincidencias.ex  albergue.ex
│   │   │   └── transiciones.ex      # máquinas de estado
│   │   ├── servidores/              # GenServers (estado + concurrencia + persistencia)
│   │   │   ├── supervisor.ex
│   │   │   └── usuarios.ex  zonas.ex  inventario.ex  necesidades.ex
│   │   │       familias.ex  mascotas.ex  albergues.ex
│   │   ├── sesiones/
│   │   │   ├── supervisor_sesiones.ex   # DynamicSupervisor
│   │   │   └── sesion.ex                # una por usuario conectado
│   │   └── cli/
│   │       ├── menu.ex              # menú numerado (opciones según el rol, conexión inteligente)
│   │       ├── consola.ex           # banner y elección de modo (menú / comandos / archivo)
│   │       ├── comandos.ex          # despacho comando → fachada, ayuda y permisos
│   │       ├── parser.ex  formato.ex
│   │       └── remoto.ex            # llama a la fachada local o en el nodo servidor (:erpc)
│   └── mix/tasks/
│       ├── consola.ex               # `mix consola`  (modo local, una sola VM; carga datos de muestra)
│       ├── servidor.ex              # `mix servidor` (nodo servidor; carga datos de muestra)
│       └── cliente.ex               # `mix cliente`  (terminal de usuario, menú o --comandos)
└── test/
    ├── test_helper.exs              # plantilla CasoSistema (reinicia datos por prueba)
    ├── dominio/                     # pruebas de funciones puras (async)
    ├── servidores/                  # GenServers, concurrencia, supervisión y persistencia
    ├── cli/                         # parser, permisos, comandos y menú numerado
    ├── datos_iniciales_test.exs     # datos de muestra: carga única, estados, usuarios con 0000
    ├── flujo_ejemplo_test.exs       # flujo completo del enunciado
    └── distribuido_test.exs         # terminales como nodos reales (:peer)
```

Regla de dependencias: `menu → comandos → (remoto) → emergencias (fachada) → servidores/sesiones/bitacora → dominio → validacion/persistencia`.
El dominio no conoce procesos; los servidores no conocen la consola.
