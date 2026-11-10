# 2.1 Diagrama de arquitectura de módulos

El sistema está organizado en capas. Cada capa solo conoce a la de abajo.

```mermaid
flowchart TB
    subgraph Usuarios["Usuarios"]
        T["Terminales de usuario<br/>cliente.bat · nodos clienteN@equipo"]
        L["Consola local<br/>mix consola (una sola VM)"]
    end

    subgraph Presentacion["Presentación y arranque"]
        CLI["<b>Consola</b> · lib/emergencias/cli<br/>CLI.Menu (menú numerado por rol)<br/>CLI.Comandos · CLI.Parser · CLI.Formato<br/>CLI.Remoto (local o :erpc.call)"]
        ARR["<b>Arranque y distribución</b><br/>mix servidor · mix cliente · mix consola<br/>Distribucion (nodos, epmd, cookie)<br/>DatosIniciales (datos de muestra)"]
    end

    subgraph Fachada["Fachada · lib/emergencias.ex"]
        F["<b>Emergencias</b><br/>permisos + validación +<br/>coordinación + bitácora"]
        AUX["Permisos (rol → MapSet)<br/>Simulacion · Demo"]
    end

    subgraph Procesos["Procesos con estado"]
        G["<b>7 GenServers</b><br/>Usuarios · Zonas · Inventario<br/>Necesidades · Familias<br/>Mascotas · Albergues"]
        S["<b>Sesiones</b><br/>SupervisorSesiones<br/>+ Sesion por usuario"]
        B["<b>Bitacora</b><br/>spawn + receive"]
        TS["<b>Task.Supervisor</b><br/>tareas paralelas"]
    end

    subgraph Base["Dominio puro y soporte"]
        D["<b>Dominio.*</b><br/>Usuario · Zona (árbol) · Necesidad · Recurso<br/>Persona · Mensaje · Mascota · Coincidencias<br/>Albergue · Transiciones"]
        P["<b>Persistencia</b><br/>datos/*.txt"]
        V["<b>Validacion</b>"]
    end

    T -- "nodo Erlang" --> CLI
    L --> CLI
    CLI -- "CLI.Remoto: :erpc.call<br/>o llamada local" --> F
    ARR -- "inicia el árbol OTP y<br/>registra datos de muestra" --> F
    F --> G & S & B & TS
    G --> D & P & V
```

## Responsabilidades

| Capa | Módulos | Responsabilidad |
|---|---|---|
| Presentación | `CLI.Menu`, `CLI.Consola`, `CLI.Comandos`, `CLI.Parser`, `CLI.Formato` | Menú numerado (solo muestra las opciones que el rol permite y pide los datos uno a uno) o comandos escritos. El menú convierte cada opción en la misma línea de comando que se escribiría a mano, así ambos modos comparten validación y formato. Al conectarse, el menú consulta si el usuario ya existe: a uno registrado solo le pide la contraseña. Sin lógica de negocio. |
| Distribución | `CLI.Remoto`, `Distribucion`, `Mix.Tasks.Servidor`, `Mix.Tasks.Cliente` | Convertir cada terminal en un nodo Erlang y ejecutar las llamadas a la fachada en el nodo servidor (`:erpc`). En modo local `Remoto` llama directo. |
| Arranque | `Mix.Tasks.*`, `DatosIniciales` | Iniciar servidor, clientes o consola local. Si no hay zonas registradas, `DatosIniciales` carga los datos de muestra (comunas de Armenia, un usuario por rol con clave `0000`, recursos, personas, necesidades, mensajes y mascotas) **a través de la fachada**, por lo que pasan por los mismos permisos y validaciones que cualquier usuario. |
| Fachada | `Emergencias` | Única API pública. Verifica permisos, valida referencias entre módulos (zona existe, albergue existe...), coordina varios GenServers y registra la actividad. |
| Procesos | `Servidores.*`, `Sesiones.*`, `Bitacora` | Dueños del estado. Serializan las operaciones concurrentes y persisten cada cambio. |
| Dominio | `Dominio.*` | Estructuras y funciones puras (validación, transiciones, cálculos, recursión). Fáciles de probar. |
| Soporte | `Persistencia`, `Validacion` | Lectura/escritura de texto plano y validaciones reutilizables. |

En modo multiusuario cada terminal (`cliente.bat`) es un nodo cliente que solo tiene
la capa de presentación; la fachada, los procesos y los datos viven en el nodo servidor
(ver [arbol_otp.md](arbol_otp.md)).

La interfaz web futura solo necesitará llamar a las funciones de `Emergencias`, igual que hace hoy la consola.
