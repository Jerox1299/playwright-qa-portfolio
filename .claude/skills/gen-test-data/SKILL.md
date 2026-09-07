---
name: gen-test-data
description: Genera datasets SQL idempotentes con casos positivos, controles y bordes para probar una query de validación en sql/. Usar cuando el usuario diga "genera datos para el check", "dataset para la validación", "test data SQL".
---

# gen-test-data

## Cuándo se dispara
El usuario nombra un check de `sql/database-validations.sql` (o describe una regla de negocio) y pide datos que lo prueben.

## Pasos
1. Leer el check objetivo en `sql/database-validations.sql` y las tablas involucradas en `sql/schema-and-seed.sql` (columnas, FKs, convención de comentarios `Q<n> MUST catch / must NOT catch`).
2. Reservar un rango de IDs que no choque con el seed (el seed usa IDs bajos; usar 9000+ salvo indicación).
3. Diseñar filas: >= 2 MUST catch, >= 2 must NOT catch, 1 por frontera (límite exacto, NULL, cero, negativo, duplicado, timestamp límite).
4. Crear padres necesarios (customer, order) en el mismo bloque para respetar FKs.
5. Escribir SQL idempotente (`ON CONFLICT DO NOTHING` o DELETE del rango reservado al inicio).
6. Comentar cada fila con la query que la atrapa o no.
7. Entregar tabla markdown fila | motivo | resultado esperado, y el comando `psql -d qa_sandbox -f <archivo>`.
8. Si es posible ejecutar (Docker/psql disponible), correr el check y confirmar que devuelve exactamente las MUST catch.

## Qué entrega
- `sql/testdata/<check>-cases.sql` (crear carpeta si no existe).
- Tabla de expectativas.
- Confirmación de ejecución o comando pendiente.

## Prohibido
Modificar filas del seed existente, UPDATE/DELETE fuera del rango reservado, filas sin comentario de expectativa.
