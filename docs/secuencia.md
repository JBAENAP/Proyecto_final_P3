# 1.7 Diagramas de secuencia

## Asignación concurrente de recursos (flujo de ejemplo del enunciado)

Laura y Carlos, cada uno en su propia terminal (nodos `cliente1` y `cliente2`), piden
al mismo tiempo 30 y 25 litros de agua; solo hay 50. Cada terminal envía la llamada
al nodo servidor con `:erpc.call(servidor, Emergencias, :asignar_recurso, args)`.

```mermaid
sequenceDiagram
    autonumber
    actor Laura as Laura (cliente1@equipo)
    actor Carlos as Carlos (cliente2@equipo)
    participant F as Emergencias (fachada, en servidor@equipo)
    participant N as Servidores.Necesidades
    participant I as Servidores.Inventario
    participant P as Persistencia (.txt)
    participant B as Bitacora

    par Peticiones simultáneas
        Laura->>F: asignar_recurso(laura, "N001", "agua", 30)
        F->>F: Permisos.autorizar(coordinador, :assign_resource)
        F->>N: GenServer.call {:asignar, N001, agua, 30}
    and
        Carlos->>F: asignar_recurso(carlos, "N002", "agua", 25)
        F->>F: Permisos.autorizar(coordinador, :assign_resource)
        F->>N: GenServer.call {:asignar, N002, agua, 25}
    end

    Note over N: El mailbox procesa un mensaje a la vez
    N->>N: Necesidad.puede_asignar(N001, 30) → :ok
    N->>I: retirar("agua", 30, preferir: [centro])
    I->>I: candidatos + Recurso.planificar_retiro/2 (recursivo)
    I->>P: guardar recursos.txt / agregar movimientos.txt
    I-->>N: {:ok, [{"R001", 30}]}  (quedan 20)
    N->>P: guardar necesidades.txt
    N-->>F: {:ok, N001 asignada, plan}
    F->>B: send {:registrar, laura, assign_resource, ok}
    F-->>Laura: OK: Asignado a N001: 30 de R001

    N->>N: Necesidad.puede_asignar(N002, 25) → :ok
    N->>I: retirar("agua", 25)
    I->>I: disponible = 20 < 25
    I-->>N: {:error, {:inventario_insuficiente, 20}}
    N-->>F: {:error, {:inventario_insuficiente, 20}} (N002 sin cambios)
    F->>B: send {:registrar, carlos, assign_resource, error}
    F-->>Carlos: ERROR: inventario insuficiente: solo hay 20 unidades
```

## Arranque del servidor con datos de muestra

```mermaid
sequenceDiagram
    autonumber
    participant M as mix servidor (servidor.bat)
    participant A as Emergencias.Application
    participant G as GenServers
    participant D as DatosIniciales
    participant F as Emergencias (fachada)
    participant P as datos/*.txt
    M->>M: Distribucion.iniciar_servidor() (--sname servidor, cookie)
    M->>A: app.start
    A->>G: start_link de cada GenServer
    G->>P: init/1 lee su archivo (estado anterior)
    M->>D: cargar_al_iniciar()
    D->>G: Zonas.arbol()
    alt ya hay zonas
        D-->>M: {:ok, :ya_habia_datos} (no se duplica nada)
    else no hay zonas (primera vez)
        D->>G: Usuarios.conectar(pedro/andres/laura/sofia, "0000", tipo...)
        D->>F: registrar_zona × 11 (comunas de Armenia + El Caimo), sectores, puntos
        D->>F: registrar_albergue, registrar_recurso, reportar_persona, registrar_ingreso
        D->>F: registrar_necesidad (+ asignar / atender / cerrar / cancelar)
        D->>F: enviar_mensaje, marcar_mensaje, reportar_mascota
        F->>G: cada operación con permisos y validaciones del rol que la hace
        G->>P: guardar cada cambio
        D-->>M: {:ok, %{creados: n, errores: []}}
    end
    M->>M: mostrar_actividad = true y vigilar() nodeup/nodedown
```

## Apertura de una terminal y conexión desde el menú

El menú pregunta primero el usuario y consulta al servidor si existe: a un usuario
registrado solo le pide la contraseña; a uno nuevo, los datos de registro.

```mermaid
sequenceDiagram
    autonumber
    actor U as Usuario
    participant T as mix cliente (nodo nuevo)
    participant E as epmd
    participant C as CLI.Menu + Comandos + Remoto (cliente)
    participant F as Emergencias (servidor)
    T->>E: nombres registrados → elige clienteN libre
    T->>T: :net_kernel.start(clienteN, hidden) + cookie
    T->>F: Node.connect(servidor@equipo) y verifica Emergencias.Supervisor
    T->>C: Consola.iniciar(:menu)
    participant US as Servidores.Usuarios
    participant DS as SupervisorSesiones (DynamicSupervisor)
    participant S as Sesion (nuevo proceso)
    participant R as Registry

    U->>C: 1 (Conectarse o registrarse) y escribe "laura"
    C->>F: :erpc.call → usuario_registrado?("laura")
    F->>US: existe?("laura")
    US-->>C: true / false
    alt registrado
        C->>U: "Usuario 'laura' registrado. Ingrese su contraseña."
        U->>C: 0000
        C->>C: construir_linea → connect laura 0000
    else nuevo
        C->>U: pide contraseña, tipo (1-4), zona y nombre
        U->>C: datos de registro
        C->>C: construir_linea → connect ana abcd voluntario comuna_5 "Ana Ruiz"
    end
    C->>F: :erpc.call → conectar(usuario, clave, tipo, zona, nombre, pid_consola)
    F->>US: conectar(...)
    alt el usuario no existe
        US->>US: Usuario.nuevo (hash SHA-256 + sal) y guardar usuarios.txt
        US-->>F: {:ok, usuario, :registrado}
    else existe y la clave es correcta
        US-->>F: {:ok, usuario, :autenticado}
    else clave incorrecta
        US-->>F: {:error, :clave_incorrecta}
        F-->>C: ERROR: contraseña incorrecta (sigue sin conectar)
    end
    opt credenciales válidas
        F->>DS: start_child({Sesion, {usuario, pid_consola}})
        DS->>S: start_link
        S->>R: registrar "laura" (único: si ya está conectada → {:error, :ya_conectado})
        S->>S: Process.monitor(pid_consola)  (pid de otro nodo)
        DS-->>F: {:ok, pid_sesion}
        F-->>C: {:ok, %{usuario, sesion}}
        C-->>U: OK: Bienvenido de nuevo / Usuario registrado y conectado
        C->>U: menú principal con las secciones que permite su rol
    end
    Note over S,C: Si la terminal se cierra, la sesión recibe :DOWN (:noconnection) y termina
```

## Terminal cliente que se cierra sin `disconnect`

```mermaid
sequenceDiagram
    participant K as Consola (cliente2@equipo)
    participant S as Sesion de carlos (servidor)
    participant R as Registry
    participant B as Bitacora
    K--xK: se cierra la ventana / cae el nodo
    S->>S: {:DOWN, ref, :process, pid_consola, :noconnection}
    S->>B: registrar(carlos, disconnect, "cliente finalizado")
    S->>S: {:stop, :normal}
    S--)R: se borra "carlos" (ya puede volver a conectarse)
```

## Búsqueda de coincidencias de mascotas (trabajo paralelo)

```mermaid
sequenceDiagram
    participant F as Emergencias
    participant M as Servidores.Mascotas
    participant Z as Servidores.Zonas
    participant T as Task.Supervisor (Tareas)
    F->>M: listar()  (copia de los reportes)
    F->>Z: mapa_raices()
    F->>T: async_stream_nolink(perdidas, comparar_con_todas)
    par una tarea por reporte perdido
        T->>T: Coincidencias.puntaje(perdida, encontrada_i)
    end
    T-->>F: pares con puntaje ≥ umbral
    F->>M: marcar_posibles(ids)  (cambio de estado atómico)
```
