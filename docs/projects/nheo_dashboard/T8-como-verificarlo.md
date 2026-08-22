# Cómo verificar T8 en tu propia máquina

Paso a paso para comprobar, con tus propias manos, que la ingesta de
eventos de Stripe funciona según lo que pide el ticket. Igual que en T7, se
recomienda una base de datos de **prueba** separada de la de desarrollo.

Se apoya en un archivo que se entrega junto con este documento (va en la
raíz de `backend/`, junto a `pyproject.toml`):

- `verificar_t8.py` — corre solo y prueba automáticamente casi todo el
  alcance (idempotencia bajo 10 reenvíos exactos, rechazo de firma
  inválida, rechazo sin header, rechazo de un timestamp viejo) sin
  necesitar tu cuenta de Stripe: firma los eventos de prueba a mano con el
  mismo secreto que le configures a la API. Al final imprime un resumen
  tipo "12/12 en PASS".

Lo que este script **no** puede probar solo es el criterio de aceptación
tal como está escrito con un pago real de Stripe — para eso están los
Pasos 4 y 5, que sí necesitan tu propia cuenta de Stripe en modo prueba.

---

## Paso 0 — Preparar el entorno

1. Abre PowerShell en la carpeta `backend` del proyecto.
2. Instala las dependencias (incluye `stripe`, que se agregó con este
   ticket):

   ```powershell
   python -m pip install -e ".[dev]"
   ```

3. Verifica que `verificar_t8.py` ya esté en `backend/`, al mismo nivel que
   `pyproject.toml`.

## Paso 1 — Una base de prueba limpia

```powershell
psql -U postgres -c "DROP DATABASE IF EXISTS nheo_test;"
psql -U postgres -c "CREATE DATABASE nheo_test;"
```

Si ya tenés `nheo_test` de la verificación de T7, sirve reciclarla igual
(bórrala y creala de nuevo como arriba, para partir de cero).

## Paso 2 — Migrar y confirmar que llega completa

```powershell
$env:DATABASE_URL = "postgresql+psycopg://postgres:TU_PASSWORD@localhost:5432/nheo_test"
alembic upgrade head
```

Tiene que terminar mostrando (entre otras) la línea
`4c7576979f2d -> 056e6e3eedd8, create stripe_events` — esa es la migración
nueva de este ticket. Si además queres confirmar el `downgrade`:

```powershell
alembic downgrade base
alembic upgrade head
```

## Paso 3 — Levantar la API y correr las verificaciones automáticas

Necesitás **dos** ventanas de PowerShell, las dos en `backend/`.

**Ventana A** — levantar la API con un secreto de prueba cualquiera (no
necesita ser el de tu cuenta real de Stripe todavía, este paso no habla con
Stripe):

```powershell
$env:DATABASE_URL = "postgresql+psycopg://postgres:TU_PASSWORD@localhost:5432/nheo_test"
$env:STRIPE_WEBHOOK_SECRET = "whsec_test_lo_que_sea"
python -m uvicorn app.main:app --port 8000
```

**Ventana B** — correr el script, con el **mismo** secreto que usaste en la
Ventana A:

```powershell
$env:DATABASE_URL = "postgresql+psycopg://postgres:TU_PASSWORD@localhost:5432/nheo_test"
$env:STRIPE_WEBHOOK_SECRET = "whsec_test_lo_que_sea"
python verificar_t8.py
```

Vas a ver una lista de líneas `[PASS]` (o `[FAIL]`), una por cada cosa que
se comprueba, y al final un resumen. Esto confirma, sin que tengas que
tocar Stripe todavía:

- que un evento nuevo, bien firmado, deja exactamente una fila;
- que reenviar el **mismo** evento diez veces (misma firma, mismo body)
  sigue dejando exactamente una fila — el criterio de aceptación del
  ticket, en su forma más literal;
- que una firma inválida se rechaza con 400 y no inserta nada;
- que falta el header `stripe-signature` se rechaza con 400;
- que un timestamp de más de 5 minutos se rechaza como posible replay,
  aunque la firma sea matemáticamente correcta para ese timestamp viejo;
- que `procesado_at` queda `NULL` — este módulo no calcula nada.

Si el resumen dice `12/12 en PASS` (o el número que corresponda), todo eso
quedó comprobado sin necesitar tu cuenta de Stripe.

## Paso 4 — Con tu cuenta real de Stripe (el criterio de aceptación tal cual está escrito)

Esta es la comprobación "con tus propias manos" que pide el ticket: *"un
pago de prueba en Stripe deja exactamente una fila, y reenviarlo diez veces
sigue dejando una."*

1. Si todavía no lo hiciste: crea o activa el **modo prueba** en tu cuenta
   de Stripe (`dashboard.stripe.com/test`), y crea un producto + precio de
   ejemplo en `dashboard.stripe.com/test/products` — un par de clics, sin
   necesitar tarjeta real ni nada que cobre dinero de verdad.
2. Instala el [Stripe CLI](https://docs.stripe.com/cli/install) si no lo
   tenés, y logueate una vez:

   ```powershell
   stripe login
   ```

3. Con la API todavía corriendo en la Ventana A del Paso 3 (o volviendo a
   levantarla si la cerraste), abrí una nueva ventana y escuchá los
   webhooks reenviándolos a tu API local:

   ```powershell
   stripe listen --forward-to localhost:8000/webhooks/stripe
   ```

   El CLI va a imprimir un secreto que empieza con `whsec_...` — **ese** es
   el que tenés que poner en `STRIPE_WEBHOOK_SECRET` de la API (reiniciá la
   Ventana A del Paso 3 con ese valor si usaste uno distinto antes). El
   secreto que da `stripe listen` es distinto al de un endpoint configurado
   en el Dashboard — no se pueden mezclar.

4. En otra ventana, disparate un evento de prueba real:

   ```powershell
   stripe trigger checkout.session.completed
   ```

   En la ventana de `stripe listen` vas a ver el evento reenviado, y en la
   Ventana A (la API) una línea de log del request. Confirmá en la base:

   ```powershell
   psql -U postgres -d nheo_test -c "SELECT stripe_event_id, tipo, procesado_at FROM stripe_events ORDER BY created_at DESC LIMIT 1;"
   ```

   Tiene que aparecer la fila, con `tipo = checkout.session.completed` y
   `procesado_at` en blanco (`NULL`).

   Un `stripe trigger checkout.session.completed` no dispara un solo
   evento: también genera `product.created`, `price.created`,
   `charge.succeeded`, `payment_intent.*`, etc. Todos quedan guardados
   igual (T8 no filtra por tipo), así que vas a ver varias filas nuevas,
   no una sola — es esperado.

## Paso 5 — Reenviar el mismo evento real diez veces

El propio Stripe CLI tiene un comando para reenviar (`resend`) un evento ya
disparado, usando su id real:

```powershell
stripe events resend <id_del_evento_que_viste_en_el_paso_4>
```

Corré ese comando diez veces (o pegalo diez veces seguidas en la terminal).
Después, confirmá que sigue habiendo una sola fila para ese
`stripe_event_id`:

```powershell
psql -U postgres -d nheo_test -c "SELECT count(*) FROM stripe_events WHERE stripe_event_id = '<el_mismo_id>';"
```

Tiene que decir `1`. Con esto queda demostrado el criterio de aceptación
completo, con un pago de prueba real y reenvíos reales de Stripe, no solo
simulados por `verificar_t8.py`.

## Resumen de qué queda demostrado

| Qué pide el ticket | Dónde se comprueba |
|---|---|
| Tabla `stripe_events` con sus columnas | Paso 2 (la migración corre sin error) |
| Verificación de la firma `stripe-signature` | Paso 3 (automático) |
| Insertar crudo y responder 200 de inmediato | Paso 3 (automático) y Paso 4 (real) |
| **Un pago de prueba deja exactamente una fila** | Paso 4 (real) |
| **Reenviarlo diez veces sigue dejando una fila** | Paso 3 (simulado) y Paso 5 (real, con el CLI) |
| Documentar que este módulo no calcula nada | `docs/T8.md`, y el `procesado_at NULL` del Paso 3/4 |

## Al terminar

Podés dejar `nheo_test` como quedó o volver a dejarla vacía:

```powershell
psql -U postgres -c "DROP DATABASE nheo_test;"
```

`verificar_t8.py` se puede borrar de `backend/` o dejarlo ahí — no afecta
nada de lo que corre en producción ni forma parte del código que se entrega
para el ticket.
