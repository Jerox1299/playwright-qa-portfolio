# Prompt · Generar dataset SQL con casos borde para una validación

Estructura de 7 partes. Copia, rellena `<...>`, pega en Claude Code dentro de este repo.

---

**Rol.** Eres un QA senior de datos, experto en PostgreSQL y en diseñar datasets que prueban queries de validación (positivos, negativos y controles).

**Contexto.** Repo `playwright-qa-portfolio`, carpeta `sql/`. `schema-and-seed.sql` define `customers`, `customer_payment_methods`, `orders`, `payments`, `audit_log` y planta defectos etiquetados. `database-validations.sql` tiene 10 checks; cada fila plantada indica qué query debe atraparla y qué query NO debe atraparla.

**Tarea.** Genera datos de prueba para la validación `<nombre o número del check>` sobre la tabla `<tabla>`, con este objetivo de negocio: `<qué regla verifica>`.

**Restricciones.**
- Mínimo: 2 filas que el check DEBE detectar, 2 filas control que NO debe detectar, y 1 caso borde por cada frontera (límite exacto, NULL, cero, negativo, duplicado, timestamp en el límite).
- SQL idempotente: `INSERT ... ON CONFLICT DO NOTHING` o DELETE previo por rango de IDs reservados (`<rango>`).
- Cada fila lleva un comentario `-- Q<n> MUST catch` o `-- Q<n> must NOT catch` como en el seed existente.
- Respeta FKs: si necesitas customer/order padre, créalos en el mismo bloque.
- No modifiques filas existentes del seed.

**Formato de salida.** Un bloque SQL listo para `psql -d qa_sandbox -f`, seguido de una tabla markdown: fila | por qué existe | resultado esperado del check.

**Ejemplo de fila esperada.**
```sql
-- Q4 MUST catch: refund exceeds collected amount
INSERT INTO payments (payment_id, order_id, amount, type, status, created_at)
VALUES (9101, 9001, -150.00, 'REFUND', 'SETTLED', '2026-01-10 10:00:00')
ON CONFLICT (payment_id) DO NOTHING;
```

**Criterio de éxito.** Al correr el check, devuelve exactamente las filas marcadas MUST catch y ninguna control. Si una fila control aparece, el dataset está mal, no la query: corrige el dataset.
