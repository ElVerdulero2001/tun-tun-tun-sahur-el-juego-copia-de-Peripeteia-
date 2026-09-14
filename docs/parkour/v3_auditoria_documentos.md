# Auditoría de documentos V3 (Parkour)

Auditoría de los cuatro documentos de diseño de Parkour V3, en el orden revisado:

1. `docs/parkour/v3_autoridad_movimiento_propuesta.md`
2. `PARKOUR_SYSTEM_ARCHITECTURE.md`
3. `docs/parkour/v3_h0_fundamento.md`
4. `docs/parkour/v3_h0_prototipo_propuesta.md`

Alcance de la auditoría: únicamente lo escrito en estos documentos. No se rediseña V3 ni se completan huecos con ideas externas.

## 1. Veredicto general

Los cuatro documentos **pueden coexistir**. La jerarquía de autoridad está declarada explícitamente y sin ciclos: `v3_autoridad_movimiento_propuesta.md` es la base; `PARKOUR_SYSTEM_ARCHITECTURE.md` se declara complementaria y subordinada a ella; `v3_h0_fundamento.md` se declara subordinado al mismo documento; `v3_h0_prototipo_propuesta.md` construye sobre el fundamento de H0 y las precondiciones heredadas de la propuesta de autoridad, sin reclamar autoridad sobre ellas.

No se encontró nada que impida un prototipo H0-only: ningún documento condiciona el funcionamiento de H0 a que Hanging, Ladder o Mantle existan, y el propio documento 4 excluye explícitamente esos cores de su alcance.

Se encontraron dos contradicciones reales de categorización/terminología (detalladas abajo), ninguna estructural: ambas se resuelven aclarando una frase, no rediseñando nada.

## 2. Problemas reales

### A. "Sprint" (doc 3) vs. "carrera rápida" (doc 1): clasificación contradictoria como core o no-core

- `v3_autoridad_movimiento_propuesta.md`, líneas 134-138, sección "Cores fuera de la predicción contextual": agrupa `Parry`, doble salto, **carrera rápida** y deslizamiento/embestida como mecánicas que "no necesitan sondas del mundo" y afirma explícitamente **"Siguen siendo cores de V3"**.
- `v3_h0_fundamento.md`, línea 49, sección "Suelo: acciones básicas sin combinaciones especiales": "Sprint es una submecánica de H0... y **no toma el gobierno como core separado**."

Si "carrera rápida" y "Sprint" nombran la misma mecánica (correr más rápido), un documento la trata como core independiente de V3 y el otro la trata explícitamente como una submecánica interna de H0, sin gobierno propio. No es un valor de ajuste abierto: es una contradicción de categoría arquitectónica (core vs. submecánica), y además choca con la regla general de vocabulario (`v3_autoridad_movimiento_propuesta.md`, línea 26) de que "los demás cores son configurables de forma independiente" — una submecánica de H0 no tiene esa independencia.

### B. "`crouch`/`Ctrl`" tratados como una sola directiva en PARKOUR_SYSTEM_ARCHITECTURE.md, contradiciendo la distinción explícita de la propuesta de autoridad

- `v3_autoridad_movimiento_propuesta.md`, línea 100: "El estado de agacharse de `H0` y mantener `Ctrl` **no son la misma regla**, aunque compartan control. Agacharse es una acción persistente de H0... Mantener `Ctrl` es una directiva compartida que... bloquea su entrada."
- `PARKOUR_SYSTEM_ARCHITECTURE.md`, línea 101, sección "Selección y gobierno del movimiento": "`crouch`/`Ctrl` es **una directiva compartida de supresión** para los cores que la consumen."

El documento 2 fusiona en una sola entidad ("crouch/Ctrl") exactamente lo que el documento 1 distingue con cuidado y llama la atención sobre no confundir ("no son la misma regla"). Como el documento 2 se declara subordinado y complementario al 1, esta redacción reintroduce la confusión que el fundamento intentó prevenir.

## 3. Decisiones abiertas legítimas

Los documentos ya las marcan como abiertas — se listan solo para confirmar que se reconocen como legítimas, no como huecos a rellenar:

- Representación técnica de la intención física por tick (tipos, campos, API).
- Si H0 debe ejecutar un tick físico obligatorio entre la salida de un core y la entrada de otro.
- Fórmulas de `X`, pesos concretos de sondas y su escala.
- Calibración final del umbral `90` (está fijado como valor provisional de trabajo, no como incógnita).
- Duración de la ventana de control aéreo total y sus parámetros físicos.
- Curva exacta de daño de caída entre 0 y el límite de 15, y la futura habilidad que la reemplazaría.
- Penalización concreta del salto agachado.
- Cómo se representa técnicamente un soporte metaestable (ancla local, transform relativo, etc.).
- Forma de agrupar los hechos de providers (snapshot vs. consulta bajo demanda).
- Si el prototipo H0-only incluye Sprint en su primera rebanada (doc 4 excluye explícitamente salto, crouch y orientación, pero no menciona Sprint).
- Relación de precedencia entre `v3_h0_prototipo_propuesta.md` y `PARKOUR_SYSTEM_ARCHITECTURE.md` (nunca se menciona directamente, pero no genera conflicto detectable hoy).

## 4. Suposiciones que NO se hicieron

- No se decide si "carrera rápida" y "Sprint" son la misma mecánica ni cuál de los dos documentos debe ceder — queda señalada la contradicción.
- No se asume un formato de contrato físico, tipos de solicitud, ni modo de colisión.
- No se asume que existe (o no) un tick obligatorio de H0 entre ejecuciones de cores.
- No se propone diseño, reglas ni entrada de Hanging, Ladder, Mantle ni ningún otro core.
- No se infieren valores de ajuste (velocidades, duraciones, penalizaciones, daño) ni se tratan como huecos arquitectónicos.
- No se asume comportamiento heredado de V1/V2 para llenar lo que estos documentos dejan abierto a propósito.
- No se decide si el cambio de collider al agacharse en el aire (`v3_h0_fundamento.md`, línea 57) debe viajar como parte de la intención física o por otra vía: el propio documento 1 deja el contrato abierto, así que no es una contradicción, es un hueco declarado.

## 5. Ajustes mínimos sugeridos

- **Sprint / carrera rápida**: agregar una frase en `v3_autoridad_movimiento_propuesta.md` o en `v3_h0_fundamento.md` que aclare si son la misma mecánica y, si lo son, unificar su clasificación (core independiente o submecánica de H0) en ambos documentos. Si son mecánicas distintas, renombrar una de las dos para evitar la colisión de nombres.
- **`crouch`/`Ctrl`**: en `PARKOUR_SYSTEM_ARCHITECTURE.md`, línea 101, separar la oración en dos ideas —el estado persistente de agacharse (H0) y la directiva temporal de mantener `Ctrl` (supresión compartida)— replicando la distinción ya hecha en `v3_autoridad_movimiento_propuesta.md`, línea 100, en vez de fusionarlas con una barra.
