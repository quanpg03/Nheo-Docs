# T0 — Contratos de integración

**Estado:** cerrado · **Fecha:** 2026-08-11 · **Dueño:** @quanpg03 · **Revisión:** 2

Fija cómo se hablan entre sí las partes del sistema. No es código: es la hoja de decisiones que
permite que Migue, Nat y yo trabajemos en paralelo sin pisarnos.

**Regla:** si algo aquí cambia, se cambia aquí primero y se avisa. Nadie "arregla" un contrato
en su propio código.

---

## Contrato 1 — El objeto `Principal`

Lo que devuelve la autenticación y lo que consume todo endpoint. Cognito valida la identidad;
**los permisos salen de nuestra base de datos**, nunca del token.

```python
class Scope(BaseModel):
    aliado_id:  UUID | None = None   # si el usuario es un aliado
    cliente_id: UUID | None = None   # si el usuario es un cliente

class Principal(BaseModel):
    user_id:      UUID
    email:        str
    nombre:       str
    capabilities: frozenset[str]     # ya expandidas, ver Contrato 2
    scope:        Scope
    roles:        list[str]          # SOLO para mostrar y depurar
    session_id:   UUID

    def can(self, capability: str) -> bool:
        return capability in self.capabilities
```

### Reglas

1. **`roles` nunca autoriza.** Está ahí para pintar "Gerencia" en el perfil y para depurar.
   Cualquier `if principal.roles == ...` en el código es un error de revisión. Se autoriza
   siempre con `can()`.
2. **Un usuario puede tener varios roles.** Las capacidades se **suman**: si alguien es vendedor
   y gerencia, tiene la unión. Nunca la intersección.
3. **`scope` puede tener ambos campos llenos.** Un aliado que además contrató a NHEO es aliado y
   cliente a la vez. Nada puede asumir que son excluyentes.
4. **El `Principal` se resuelve en cada request**, leyendo `user_roles`. No se cachea entre
   requests. Es lo que hace que revocarle un rol a alguien tenga efecto inmediato en vez de
   esperar 8 horas a que expire su token.
5. `session_id` existe para revocar sesiones individuales (SEG-14).

### Rutas de autoservicio (sin capacidad)

Algunas rutas no requieren capacidad, solo estar autenticado, y siempre operan sobre uno mismo:

```
GET/PATCH /auth/perfil          GET /auth/sesiones      DELETE /auth/sesiones/{id}
GET       /notificaciones       POST /notificaciones/{id}/leer
GET/PATCH /notificaciones/preferencias
```

Están enumeradas aquí a propósito. **Cualquier ruta que no esté en esta lista lleva
`requires(...)` obligatorio**, y el test de T6 recorre el router verificando que no haya
ninguna sin proteger. Las encuestas que responde el cliente (CSAT y NPS) se contestan por
enlace con token de un solo uso, fuera de la sesión: tampoco llevan capacidad.

---

## Contrato 2 — Catálogo de capacidades

**67 capacidades**, formato `recurso:accion`. Base: las 6 matrices de permisos del documento
técnico §3, más las desviaciones registradas al final de esta sección.

### Vocabulario de acciones

| Acción | Significa |
|---|---|
| `read` | Ver, limitado a lo mío (mi cartera, mis asignados, mis referidos) |
| `read_all` | Ver todo, sin restricción de pertenencia |
| `create` / `edit` | Crear / modificar |
| `export` | Descargar en CSV o Excel |
| `approve` | Aprobar en un flujo (comisiones, gastos, viajes) |
| `adjust` | Emitir una corrección contable |
| `execute` / `manage` / `reconcile` / `pay` | Acciones con efecto externo sobre dinero |
| `admin` | Administración completa del recurso |

### Tres reglas de resolución

1. **`read_all` reemplaza a `read`.** Al construir el `Principal`, si el usuario tiene
   `X:read_all` se le añade `X:read` automáticamente. **En la matriz de abajo solo se marca
   `read_all`** — marcar ambas sería redundante y hace ambiguo cualquier conteo.
2. **El alcance de escritura es igual al de lectura.** Con `clientes:edit` y solo
   `clientes:read`, editas tu cartera. Con `read_all`, editas todo. No existen `edit_all` ni
   `create_all`: sería un tercer eje que nadie mantiene bien.
3. **En `create`, el alcance se valida con `WITH CHECK`, no con `USING`.** No hay fila previa
   contra la cual evaluar pertenencia, así que la política RLS debe verificar la fila **nueva**:
   un vendedor no puede crear un cliente con `vendedor_id` de otro, y un cliente no puede abrir
   un ticket sobre un `proyecto_id` ajeno. Sin `WITH CHECK` el aislamiento se puede burlar
   escribiendo en vez de leyendo.

### El catálogo

```
# Usuarios y auditoría (3)
usuarios:read              usuarios:admin             auditoria:read

# Clientes (5)
clientes:read              clientes:read_all          clientes:create
clientes:edit              clientes:export

# Proyectos (5)
proyectos:read             proyectos:read_all         proyectos:create
proyectos:edit             proyectos:read_internal

# Tareas y bloqueos (4)
tareas:read                tareas:create              tareas:edit
bloqueos:create

# Comunicación con el cliente (4)
actualizaciones:read       actualizaciones:publish
conversacion:read          conversacion:write

# Tickets (5)
tickets:read               tickets:read_all           tickets:create
tickets:respond            tickets:assign

# Facturas (5)
facturas:read              facturas:read_all          facturas:create
facturas:edit              facturas:export

# Pagos y suscripciones (5)
pagos:read                 pagos:read_all             pagos:pay
pagos:manage               pagos:reconcile

# Comisiones (5)
comisiones:read            comisiones:read_all        comisiones:approve
comisiones:adjust          comisiones:export

# Aliados (6)
aliados:read               aliados:create             aliados:edit
aliados:assign_client      pagos_aliados:read         pagos_aliados:execute

# Gastos, actividades y viajes (9)
gastos:read                gastos:create              gastos:edit
gastos:approve             actividades:read           actividades:create
viajes:read                viajes:create              viajes:approve

# Encuestas (2)
encuestas:read             encuestas:manage

# Reportes y finanzas (7)
kpis:read                  kpis:read_all              reportes:read
reportes:configure         reportes:export            finanzas:read
finanzas:export

# Sistema (2)
config:manage              jobs:admin
```

### Seis capacidades que merecen explicación

**`proyectos:read_internal`** — separa las notas internas del resto del proyecto. Sin ella no
ves la pestaña de notas internas aunque puedas ver el proyecto. Es lo que impide que el aliado
o el cliente vean *"parche feo para la API legacy del cliente"*.

**`actualizaciones:publish` vs `conversacion:write`** — son cosas distintas y por eso son dos
capacidades. `actualizaciones` es la bitácora curada que el equipo redacta en un sentido;
`conversacion` es el hilo de ida y vuelta con el cliente. El cliente puede escribir en el
segundo, nunca en el primero.

**`comisiones:adjust`** — el documento §3-A le da a Gerencia "Editar" sobre comisiones. Con el
ledger append-only eso no existe: editar es **emitir un evento de corrección**. Esta capacidad
es la traducción, y es la más sensible del sistema: quien la tiene puede mover dinero que ya se
calculó. Va separada de `approve` a propósito, para que aprobar un lote y corregir un monto no
sean el mismo permiso.

**`pagos:manage`** — pausar y cancelar suscripciones, y emitir reembolsos. Efecto irreversible
sobre dinero de un cliente real.

**`bloqueos:create`** — separada de `proyectos:edit` porque §5.5 dice que *cualquier miembro del
equipo* puede registrar un bloqueo, incluido un vendedor que no debería poder editar el
proyecto.

**`config:manage`** — SLA por plan, umbral de alerta de comisión, pesos de las fases. Cambiar un
peso cambia el % de avance que ve el cliente: no es una pantalla inocente.

### Matriz rol → capacidades

Recuerda la regla 1: donde aparece `read_all` no se marca `read`, se deriva.

| Capacidad | Gerencia | Ventas | Desarrollo | Cliente | Admin | Aliado |
|---|:--:|:--:|:--:|:--:|:--:|:--:|
| usuarios:read | ● | | | | | |
| usuarios:admin | ● | | | | | |
| auditoria:read | ● | | | | | |
| clientes:read | | ● | ● | | | ● |
| clientes:read_all | ● | | | | ● | |
| clientes:create | | ● | | | ● | |
| clientes:edit | ● | ● | | | ● | |
| clientes:export | ● | | | | ● | |
| proyectos:read | | ● | ● | ● | | ● |
| proyectos:read_all | ● | | | | | |
| proyectos:create | | ● | | | | |
| proyectos:edit | | | ● | | | |
| proyectos:read_internal | ● | | ● | | | |
| tareas:read | ● | | ● | | | |
| tareas:create | | | ● | | | |
| tareas:edit | | | ● | | | |
| bloqueos:create | ● | ● | ● | | | |
| actualizaciones:read | ● | | ● | ● | | |
| actualizaciones:publish | | | ● | | | |
| conversacion:read | ● | | ● | ● | | |
| conversacion:write | | | ● | ● | | |
| tickets:read | | ● | ● | ● | | |
| tickets:read_all | ● | | | | | |
| tickets:create | | | ● | ● | | |
| tickets:respond | | | ● | ● | | |
| tickets:assign | | | ● | | | |
| facturas:read | | | | ● | | |
| facturas:read_all | ● | | | | ● | |
| facturas:create | | | | | ● | |
| facturas:edit | | | | | ● | |
| facturas:export | ● | | | | ● | |
| pagos:read | | ● | ● | ● | | ● |
| pagos:read_all | ● | | | | ● | |
| pagos:pay | | | | ● | | |
| pagos:manage | | | | | ● | |
| pagos:reconcile | | | | | ● | |
| comisiones:read | | ● | ● | | | ● |
| comisiones:read_all | ● | | | | ● | |
| comisiones:approve | ● | | | | ● | |
| comisiones:adjust | ● | | | | | |
| comisiones:export | ● | | | | ● | ● |
| aliados:read | ● | | | | ● | |
| aliados:create | | | | | ● | |
| aliados:edit | | | | | ● | |
| aliados:assign_client | | | | | ● | |
| pagos_aliados:read | ● | | | | ● | ● |
| pagos_aliados:execute | | | | | ● | |
| gastos:read | ● | | | | ● | |
| gastos:create | | | | | ● | |
| gastos:edit | ● | | | | ● | |
| gastos:approve | ● | | | | | |
| actividades:read | ● | ● | ● | | | |
| actividades:create | | ● | ● | | | |
| viajes:read | ● | ● | ● | | | |
| viajes:create | | ● | ● | | | |
| viajes:approve | ● | | | | | |
| encuestas:read | ● | | | | ● | |
| encuestas:manage | | | | | ● | |
| kpis:read | | ● | ● | | ● | |
| kpis:read_all | ● | | | | | |
| reportes:read | ● | | | | ● | |
| reportes:configure | ● | | | | | |
| reportes:export | ● | | | | ● | |
| finanzas:read | ● | | | | ● | |
| finanzas:export | ● | | | | ● | |
| config:manage | ● | | | | | |
| jobs:admin | ● | | | | | |

**Totales (verificados contando la tabla):** Gerencia 37 · Ventas 14 · Desarrollo 23 ·
Cliente 10 · Admin 30 · **Aliado 6**. Suma de marcas: 120 sobre 402 celdas posibles.

### Las 6 capacidades del Aliado

`clientes:read` · `proyectos:read` · `pagos:read` · `comisiones:read` · `comisiones:export` ·
`pagos_aliados:read`

**Todas de lectura, ninguna de escritura.** Cualquier PR que agregue una capacidad a esta
columna pasa por mí sin excepción. El test de aislamiento de T6 debe verificar exactamente
estas 6 y fallar si aparece una séptima.

Fíjate en lo que **no** tiene: `actualizaciones:read` ni `conversacion:read`. El documento
§5.6 dice literalmente que el aliado no accede a comunicaciones internas, y su vista de
proyectos es "resumen: fase + % avance". Darle la bitácora del cliente sería filtrar la
relación comercial de NHEO con ese cliente. `pagos:read` sí lo tiene porque §3-F y §6.6 le
prometen ver si el cliente está "pagando/atrasado" y su "último pago".

### Desviaciones registradas respecto al documento §3

El §3 no cubre todo el sistema, así que estas capacidades **no** salen de sus matrices. Se
listan para que nadie las tome por error de transcripción.

| Capacidad y rol | De dónde sale | Por qué |
|---|---|---|
| Las 27 de Admin sobre clientes, aliados, comisiones y encuestas | §6.1, §6.2, §6.4, §4.12 | §3-E solo enumera facturas, gastos, suscripciones, caja, reportes, conciliación y pagos a aliados, pero §6 le asigna a Admin todo el ciclo del aliado |
| `tickets:read_all` a Gerencia | §9.1 | Necesita el KPI "Tickets Abiertos" |
| `tickets:create`, `tickets:assign` a Desarrollo | §4.7, SOP-03 | El equipo abre tickets a nombre del cliente; la asignación es automática pero alguien debe poder reasignar |
| `proyectos:create` a Ventas | §8 Flujo 1 | "Admin/Ventas crea el cliente… se crea el proyecto inicial" |
| `bloqueos:create` a Ventas y Gerencia | §5.5 | "Cualquier miembro del equipo puede registrar un bloqueo" |
| `kpis:read` a Ventas y Desarrollo | §3-C, §3-B | "Métricas de ventas propias" y el dashboard propio del dev |
| `comisiones:adjust` a Gerencia | §3-A "Editar" | Traducción de "editar" al modelo append-only |
| `viajes:read/create` a Ventas y Desarrollo | §4.10 | §3 solo menciona la aprobación; alguien tiene que solicitarlos |
| **`tareas:read` NEGADO al Cliente** | decisión propia | §3-D y §5.6 se lo dan, pero decidimos sustituirlo por la bitácora curada (DAT-07). **Es una desviación deliberada del documento original** |
| **`facturas:read` y `actualizaciones:read` NEGADOS a Ventas** | decisión propia | §3-C le da "estado de pagos", que resolvemos con `pagos:read`. Si en la práctica el vendedor necesita ver la factura, se agrega — pero que sea una decisión, no un descuido |

---

## Contrato 2b — Cómo llega el alcance a RLS

Al abrir cada transacción, antes de cualquier consulta:

```python
# set_config, NUNCA "SET LOCAL app.x = '<valor>'" con interpolación de cadenas
await session.execute(
    text("SELECT set_config('app.current_user_id',   :uid, true),"
         "       set_config('app.current_aliado_id',  :ali, true),"
         "       set_config('app.current_cliente_id', :cli, true),"
         "       set_config('app.scope_clientes',     :sc,  true),"
         "       set_config('app.scope_proyectos',    :sp,  true),"
         "       set_config('app.scope_facturas',     :sf,  true),"
         "       set_config('app.scope_pagos',        :spa, true),"
         "       set_config('app.scope_tickets',      :st,  true),"
         "       set_config('app.scope_comisiones',   :sco, true)"),
    {...}
)
```

### Por qué hay un alcance por recurso y no uno global

**Esto era un bug grave en la revisión 1 y vale la pena entender por qué.**

La primera versión fijaba un solo booleano, `app.ve_todo = true si tiene alguna capacidad
:read_all`. Admin tiene `clientes:read_all`, `facturas:read_all`, `pagos:read_all` y
`comisiones:read_all` — así que `ve_todo` habría sido `true`, y las políticas RLS de
**proyectos, tareas y tickets** le habrían devuelto todas las filas. Justo lo contrario de lo
que dice §3-E, que le niega a Admin el acceso a proyectos de desarrollo.

Con Gerencia el error habría pasado desapercibido, porque su `ve_todo = true` coincide con lo
deseado. Se habría descubierto en producción, con un administrativo viendo notas de proyectos.

**Regla:** `app.scope_<recurso>` vale `'all'` u `'own'`, y se deriva de la capacidad
`<recurso>:read_all` de **ese recurso concreto**. Nunca de la presencia de cualquier otra.

`tareas` y `actualizaciones` heredan `app.scope_proyectos`; no tienen GUC propio.

### Detalles que rompen si se ignoran

- Los GUC son **texto**. Un `aliado_id` nulo llega como cadena vacía, y `''::uuid` lanza
  `invalid input syntax`. En las políticas: `NULLIF(current_setting('app.current_aliado_id', true), '')::uuid`.
- Siempre `current_setting(..., true)` (la forma de dos argumentos). Sin el `true`, una
  variable no fijada lanza error `42704` en vez de devolver `NULL`.
- `set_config(..., true)` es *local a la transacción*, que es lo que queremos con pooling.
- **Migue: verifica esto explícitamente en T6.** Es el punto exacto donde RLS y el pool de
  conexiones se pelean, y donde vive el plan B documentado en SEG-10.

### El worker no tiene `Principal`

`comision.calcular`, `stripe.reconciliar_dia` y `email.enviar` corren en el servicio `worker`,
sin request y sin usuario. Si intentan operar bajo estas políticas, todas las consultas
devuelven cero filas.

**Decisión:** el worker se conecta con un rol de base de datos distinto, `nheo_worker`, con
`BYPASSRLS`, y su propio pool de conexiones. La API nunca usa ese rol.

**A cambio de esa potencia, dos reglas obligatorias:**
1. Todo query del worker filtra explícitamente por tenant en el código. RLS ya no lo protege.
2. Ningún endpoint HTTP puede terminar ejecutándose bajo `nheo_worker`. Que sean pools
   separados no es cosmético: es lo que hace que un error de importación no le dé a un request
   de un aliado acceso total.

*Alternativa considerada y rechazada:* un GUC `app.is_system = 'true'` con una cláusula `OR` en
cada política. Más simple de montar, pero deja el bypass total a una cadena de distancia dentro
del mismo pool que atiende a los aliados. El rol separado hace el error mucho menos probable.

---

## Contrato 3 — Respuestas HTTP

### Éxito: cuerpo desnudo

```http
GET /api/v1/clientes/018f2a...
200 OK

{ "id": "018f2a...", "nombre_empresa": "Distribuidora El Roble SAS",
  "estado": "ACTIVO", "mrr": "2400000.00", "created_at": "2026-03-15T14:22:00Z" }
```

Listas, siempre igual:

```http
GET /api/v1/clientes?limit=50&cursor=eyJjIjoi...
200 OK

{ "items": [ {...}, {...} ], "next_cursor": "eyJjIjoi...", "prev_cursor": null }
```

- **Orden por defecto: `created_at DESC, id DESC`.** El `id` es el desempate y es obligatorio:
  sin él, dos filas con el mismo timestamp hacen que el cursor salte o repita registros.
- El cursor es opaco: base64 de `{"created_at": ..., "id": ...}`. El frontend no lo interpreta.
- **`limit` por defecto 50, máximo 200.** Un `?limit=100000` se recorta a 200, no da error.
- Hay `prev_cursor` porque el diseño usa botones anterior/siguiente. `null` en los extremos.
- **No hay conteo total.** Contar con filtros es caro y el diseño ya decidió no mostrar números
  de página.

Creación devuelve **201** con el objeto. Acciones sin cuerpo, **204**.

### Operaciones por lote

`POST /api/v1/comisiones/aprobar-lote` no puede devolver 204: hay que saber qué se aprobó y qué
no. Devuelve **200** con:

```json
{
  "procesados": 47,
  "fallidos": [
    { "id": "018f...", "code": "COMISION_YA_APROBADA",
      "message": "Esta comisión ya fue aprobada." }
  ]
}
```

### Error: siempre envuelto

Conflicto de estado (409) — sin `details`:

```json
{ "error": {
    "code": "COMISION_YA_APROBADA",
    "message": "Esta comisión ya fue aprobada y no se puede modificar.",
    "request_id": "01J8XQ2M4K7P9R" } }
```

Validación (422) — con `details`:

```json
{ "error": {
    "code": "VALIDACION",
    "message": "Revisa los campos marcados.",
    "details": [ { "field": "porcentaje", "message": "Debe estar entre 0 y 100" } ],
    "request_id": "01J8XQ2M4K7P9R" } }
```

| Campo | Para qué |
|---|---|
| `code` | Estable, en mayúsculas, para que el frontend decida. **Nunca cambia** una vez publicado |
| `message` | En español, listo para mostrar. Sin jerga técnica |
| `details` | **Solo en 422.** Es lo que pinta los errores bajo cada campo del formulario |
| `request_id` | Igual al header `X-Request-Id`. Es lo que el usuario reporta y lo que buscamos en Sentry |

**`X-Request-Id`**: la API lo acepta si viene, y si no lo genera. Va en la respuesta de **todo**
request, con éxito o con error, y en todas las líneas de log (OPS-02).

### Códigos de estado

| Código | Cuándo | Qué hace el frontend |
|---|---|---|
| 400 | Petición mal formada | Mostrar `message` |
| 401 | Token vencido | Refrescar y reintentar |
| 401 + `code: SESION_REVOCADA` | Sesión cerrada desde otro lado o rol revocado | **No refrescar.** Ir directo a login |
| 403 | Le falta la **capacidad** | Pantalla "sin permiso" |
| 404 | No existe **o no lo puede ver** | Pantalla "no encontrado" |
| 409 | Conflicto de estado | Mostrar `message` y recargar |
| 422 | Validación de campos | Pintar `details` bajo cada campo |
| 429 + header `Retry-After` | Demasiadas peticiones | Esperar los segundos que indique |
| 500 | Error nuestro | Pantalla de error con el `request_id` |

**El 401 con `SESION_REVOCADA` no es un detalle.** Sin él: revocamos la sesión en nuestra base,
pero el refresh token sigue siendo válido en Cognito, así que el frontend refresca con éxito,
vuelve a recibir 401, refresca otra vez — bucle infinito contra Cognito.

### La regla del 404

**Si RLS filtra una fila, la API devuelve 404, no 403.** Para un aliado que pide el cliente de
otro aliado, ese cliente sencillamente no existe.

Es deliberado: un 403 confirmaría que el recurso existe, y eso ya es una fuga — un aliado podría
enumerar IDs para saber cuántos clientes tiene NHEO. El 403 se reserva para cuando le falta la
**capacidad**, no el **alcance**.

Dos casos derivados, para que dos devs no los resuelvan distinto:
- **Un `PATCH` cuyo `UPDATE` afecta 0 filas por RLS → 404.** No 403, no 200 silencioso.
- **Un `POST` cuyo cuerpo referencia un id fuera de alcance** (crear un ticket sobre un proyecto
  ajeno) → **422 con `details` sobre ese campo**, no 404. Es un error de formulario, no de ruta.

### Nota de implementación

FastAPI devuelve por defecto `{"detail": [...]}`, que no es este contrato. Hay que registrar
`exception_handler` para `RequestValidationError` y `HTTPException` que los normalice. Media
hora en T1, y evita que el frontend maneje dos formatos.

---

## Contrato 4 — Encolado de trabajos

```python
def enqueue(
    job_type: str,
    payload: dict,
    *,
    run_at: datetime | None = None,        # None = lo antes posible
    idempotency_key: str | None = None,
    max_attempts: int = 5,
) -> UUID:                                  # id del job, nuevo o el existente
    ...
```

### Cinco reglas

**1. `enqueue()` va dentro de la misma transacción que la escritura de dominio.**
Es la ventaja de tener la cola en Postgres y no en Redis: si la transacción se revierte, el
trabajo también. Nunca queda encolado un correo de "comisión generada" para una comisión que no
se guardó.

**2. La deduplicación usa `ON CONFLICT DO NOTHING`, nunca una excepción.**

```sql
INSERT INTO jobs (id, job_type, payload, run_at, idempotency_key, max_attempts)
VALUES (...)
ON CONFLICT (job_type, idempotency_key) DO NOTHING
RETURNING id;
-- si no devolvió fila: SELECT id FROM jobs WHERE job_type = ... AND idempotency_key = ...
```

**Esto era un bug en la revisión 1.** Decía "restricción UNIQUE" a secas: un segundo `INSERT`
con la misma llave habría lanzado `IntegrityError`, y en Postgres eso **aborta la transacción
completa**, revirtiendo la escritura de dominio que la envolvía. El procesador de eventos de
Stripe habría perdido escrituras la primera semana. `enqueue()` **nunca lanza por duplicado**:
devuelve el id del trabajo existente.

**3. La llave de idempotencia protege el encolado, no la ejecución.**
Con reintentos la entrega es *al menos una vez*: si el worker muere después de insertar la
comisión y antes de marcar el trabajo, el reintento la inserta otra vez.

> **La que realmente salva es la restricción `UNIQUE` de dominio sobre `commission_events`,
> no la de `jobs`.** Y todo manejador debe ser idempotente: comprobar si su efecto ya ocurrió
> antes de aplicarlo. Nat: esto es requisito de aceptación de T8 y del motor de comisiones.

**4. `idempotency_key` es obligatoria en los trabajos de dinero.**
La lista, explícita y verificada en tiempo de ejecución por `enqueue()`:
`comision.calcular` · `comision.corregir` · `pago_aliado.registrar` · `stripe.procesar_evento`.
Llamar a uno de estos sin llave lanza `ValueError` en desarrollo y en producción. No es una
recomendación en prosa: es una comprobación.

**5. El `payload` guarda identificadores, no objetos.**
`{"comision_id": "018f..."}`, nunca la comisión serializada. Cuando el trabajo se ejecute —quizá
20 minutos después por un reintento— los datos pueden haber cambiado, y el worker debe leer el
estado actual.

### Reproceso: por qué la llave lleva `run_id`

COM-08 exige poder recalcular todo el histórico desde `stripe_events` cuando cambien las reglas
de comisión. Con una llave eterna, reencolar los mismos eventos **no encolaría nada, en
silencio**, porque todas las llaves ya existirían.

Por eso la llave de los trabajos de recálculo lleva un discriminador de corrida:
`recalc:{run_id}:{stripe_event_id}`. Cada reproceso usa un `run_id` nuevo. Las llaves de la
operación normal no lo llevan.

Además, un job de mantenimiento purga las filas de `jobs` completadas con más de 90 días.

### Semántica de ejecución

| Aspecto | Decisión |
|---|---|
| Toma de trabajos | `SELECT ... FOR UPDATE SKIP LOCKED`, lotes de 10 |
| Sondeo | Cada **2 segundos**. HU-031 exige comisión calculada en ≤2 minutos con dos saltos asíncronos; con sondeo de 30s no se cumple |
| Arrendamiento | `locked_at` + `locked_by`. Un trabajo tomado hace más de **5 minutos** se considera huérfano y vuelve a la cola. Sin esto, un worker que muere deja el trabajo tomado para siempre |
| Reintentos | Espera exponencial: 10s, 40s, 3min, 12min, 50min |
| Al agotar `max_attempts` | Pasa a `AGOTADO`, sale de la cola, y dispara alerta si el `job_type` es de dinero |
| Reproceso manual | Desde la pantalla 117, que reencola con `run_id` nuevo |

### Nombres de trabajos

`dominio.accion`, en minúscula: `stripe.procesar_evento` · `stripe.reconciliar_dia` ·
`comision.calcular` · `comision.corregir` · `pago_aliado.registrar` · `email.enviar` ·
`notificacion.despachar` · `proyecto.notificar_hito`.

---

## Contrato 5 — Dueño de las migraciones

**Dueña única: Nat.** Ya tiene T4 (migraciones), T7 (cola) y T8 (Stripe): todo el carril de
datos. Quien escribe el esquema es quien lo conoce.

- **Nadie más crea archivos en `backend/alembic/versions/`.** Ni Migue ni yo.
- Si necesitas una columna o una tabla, abres un ticket con el campo, el tipo y para qué es.
  Nat la escribe. En la práctica es la misma tarde.
- `CODEOWNERS`: `/backend/alembic/ @nat`.
- **Toda migración tiene `downgrade()` que funciona**, probado antes del merge.
- Las migraciones se aplican como **paso previo al despliegue**, nunca al arrancar la
  aplicación: dos contenedores arrancando a la vez correrían la misma migración dos veces.

**Por qué una sola persona:** Alembic mantiene una cadena lineal de revisiones. Si dos personas
crean una migración desde la misma cabeza, aparecen dos cabezas y el despliegue falla hasta que
alguien las fusiona a mano. Con tres personas en paralelo eso pasa la primera semana.

---

## Anexo — Convenciones

No estaba en el ticket de T0, pero si no se fija ahora se decide tres veces distinto.

**Identificadores.** UUID como llave primaria en todas las tablas, generado en la aplicación.
Usar **UUIDv7** (ordenado por tiempo) en vez de v4: los índices se fragmentan mucho menos porque
las inserciones van al final del árbol. *Nat: verifica si la versión de Postgres que quedó en
RDS trae `uuidv7()` nativo; si no, se genera desde Python con una librería.*

**Tiempo.** Todo en UTC, en columnas `TIMESTAMPTZ`. La conversión a hora de Bogotá se hace solo
al presentar. Ninguna consulta filtra por hora local.

**Dinero.** `NUMERIC(14,2)`, nunca `float`. La moneda va en su propia columna `CHAR(3)` aunque
hoy solo exista `COP`: agregarla después obliga a migrar datos financieros. Los porcentajes
también `NUMERIC`, guardados como `10.00` para 10%.

**Nombres.** Tablas en plural y en español (`clientes`, `comisiones`), como en el documento
técnico. Columnas en `snake_case`. Llaves foráneas `<tabla_singular>_id`. Toda tabla lleva
`created_at` y `updated_at`.

**Rutas.** `/api/v1/<recurso>` en plural. Los verbos que no son CRUD van como subrecurso:
`POST /api/v1/comisiones/aprobar-lote`.

---

## Definición de terminado

- [x] `Principal` definido, con la regla de que los roles no autorizan
- [x] 67 capacidades, matriz de los 6 roles y desviaciones registradas
- [x] Alcance por recurso hacia RLS, y contexto del worker resuelto
- [x] Formato de éxito, de error, códigos de estado y las reglas del 404
- [x] `enqueue()` con deduplicación que no aborta la transacción
- [x] Nat como dueña única de las migraciones
- [ ] Publicado en el README del repo (bloqueado por T1)

**Los tres carriles ya pueden mockear lo que no existe y seguir trabajando.**
