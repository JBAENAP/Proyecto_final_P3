# 1.6 Modelo de datos

```mermaid
classDiagram
    direction TB

    class Usuario {
        username : String  «id»
        hash : String
        sal : String
        nombre_completo : String
        tipo : ciudadano|voluntario|coordinador|administrador
        zona : String
        creado_en : NaiveDateTime
    }

    class Zona {
        codigo : String  «id»
        nombre : String
        tipo : zona|sector|punto
        nivel : critico|alto|medio|bajo
        personas : Integer
        categoria : String
        hijos : List~Zona~
    }

    class Necesidad {
        id : String  «N001»
        tipo : agua|alimentos|medicamentos|primeros_auxilios|refugio|transporte|rescate|otra
        descripcion : String
        cantidad : Integer
        asignada : Integer
        zona : String
        prioridad : critica|alta|media|baja
        responsable : String
        estado : pendiente|asignada|en_atencion|atendida|cancelada
        asociado_tipo : zona|persona|familia|albergue
        asociado_ref : String
        asignaciones : List~Tuple codigo, cantidad~
        creada_en : NaiveDateTime
    }

    class Recurso {
        codigo : String  «id»
        nombre : String
        categoria : String
        cantidad : Integer ≥ 0
        unidad : String
        ubicacion : String
        zona : String
        creado_en : NaiveDateTime
    }

    class Movimiento {
        fecha : NaiveDateTime
        tipo : registro|entrada|salida|asignacion|transferencia_salida|transferencia_entrada
        codigo : String
        cantidad : Integer
        saldo : Integer
        referencia : String
        usuario : String
    }

    class Persona {
        id : String  «P001»
        documento : String  «único»
        nombre : String
        edad : Integer
        zona : String
        estado : sin_informacion|reportada|localizada|trasladada|en_albergue|reunificada
        familia : String
        historial : List~Tuple fecha, desde, hacia, usuario, detalle~
    }

    class Mensaje {
        id : String  «M001»
        fecha : NaiveDateTime
        remitente : String
        destinatario : documento | familia:X
        contenido : String
        estado : pendiente|entregado
    }

    class Mascota {
        id : String  «PET001»
        tipo_reporte : perdida|encontrada
        especie : String
        nombre : String
        caracteristicas : String
        color : String
        tamano : pequeno|mediano|grande
        zona : String
        contacto : String
        estado : activa|posible_coincidencia|resuelta
        coincidencia_con : String
    }

    class Albergue {
        codigo : String  «id»
        nombre : String
        zona : String
        capacidad : Integer > 0
        ocupacion : Integer ≤ capacidad
        ocupantes : MapSet~documento~
    }

    Zona "1" *-- "0..*" Zona : hijos (zona→sector→punto)
    Zona "1" o-- "0..*" Albergue : zona
    Zona "1" o-- "0..*" Necesidad : zona
    Zona "1" o-- "0..*" Recurso : ubicacion / zona
    Zona "1" o-- "0..*" Persona : zona
    Zona "1" o-- "0..*" Mascota : zona
    Albergue "1" o-- "0..*" Recurso : ubicacion
    Albergue "0..1" o-- "0..*" Necesidad : asociado_a
    Albergue "1" o-- "0..*" Persona : ocupantes
    Persona "0..1" o-- "0..*" Necesidad : asociado_a
    Recurso "1" *-- "0..*" Movimiento : historial
    Necesidad "1" o-- "0..*" Recurso : asignaciones
    Persona "1" o-- "0..*" Mensaje : destinatario
    Mascota "0..1" -- "0..1" Mascota : coincidencia_con
    Usuario "1" o-- "0..*" Necesidad : responsable
    Usuario "1" o-- "0..*" Mensaje : remitente
```

## Máquinas de estado (`Dominio.Transiciones`)

Cada máquina es un mapa `estado => MapSet de destinos válidos`. Los estados sin salidas
son terminales: un registro en ese estado ya no puede modificarse ni cerrarse de nuevo.

```mermaid
stateDiagram-v2
    state "Necesidad" as N {
        [*] --> pendiente
        pendiente --> asignada
        pendiente --> en_atencion
        pendiente --> cancelada
        asignada --> en_atencion
        asignada --> cancelada
        en_atencion --> atendida
        en_atencion --> cancelada
        atendida --> [*]
        cancelada --> [*]
    }
```

```mermaid
stateDiagram-v2
    state "Persona" as P {
        [*] --> reportada
        sin_informacion --> reportada
        sin_informacion --> localizada
        sin_informacion --> trasladada
        sin_informacion --> en_albergue
        reportada --> localizada
        reportada --> trasladada
        reportada --> en_albergue
        reportada --> reunificada
        localizada --> trasladada
        localizada --> en_albergue
        localizada --> reunificada
        trasladada --> localizada
        trasladada --> en_albergue
        trasladada --> reunificada
        en_albergue --> localizada
        en_albergue --> trasladada
        en_albergue --> reunificada
        reunificada --> [*]
    }
```

```mermaid
stateDiagram-v2
    state "Mascota" as M {
        [*] --> activa
        activa --> posible_coincidencia
        posible_coincidencia --> activa
        activa --> resuelta
        posible_coincidencia --> resuelta
        resuelta --> [*]
    }
```

```mermaid
stateDiagram-v2
    state "Mensaje" as E {
        [*] --> pendiente
        pendiente --> entregado
        entregado --> pendiente
    }
```

Una persona puede registrarse directamente en cualquier estado (por defecto `reportada`).

## Archivos de texto plano (`datos/`)

| Archivo | Contenido | Escritura |
|---|---|---|
| `usuarios.txt` | `username\|hash\|sal\|nombre\|tipo\|zona\|creado_en` | reescritura atómica |
| `zonas.txt` | `codigo\|nombre\|tipo\|nivel\|personas\|categoria\|padre` (preorden) | reescritura atómica |
| `necesidades.txt` | una necesidad por línea, asignaciones como `R001:30;R002:5` | reescritura atómica |
| `recursos.txt` | un recurso por línea | reescritura atómica |
| `movimientos.txt` | historial de inventario | solo inserción |
| `personas.txt` / `historial_personas.txt` | personas / cambios de estado | reescritura / solo inserción |
| `mensajes.txt`, `mascotas.txt`, `albergues.txt` | un registro por línea (ocupantes como `doc1;doc2`) | reescritura atómica |
| `actividad.txt` | bitácora de acciones por usuario | solo inserción |
