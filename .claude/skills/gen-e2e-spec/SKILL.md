---
name: gen-e2e-spec
description: Genera un spec E2E de Playwright (POM, web-first) a partir de una historia de usuario. Usar cuando el usuario diga "genera el spec para", "cubre esta HU", "nuevo test E2E de".
---

# gen-e2e-spec

## Cuándo se dispara
El usuario entrega una historia de usuario o criterios de aceptación y pide cobertura E2E en `tests/ui/`.

## Pasos
1. Leer `CLAUDE.md` (reglas duras) y el spec más parecido en `tests/ui/` para copiar el estilo.
2. Listar `pages/` y `data/`. Decidir qué Page Objects y datos se reutilizan y cuáles faltan.
3. Convertir cada criterio de aceptación en un nombre de test que se lea como requisito. Añadir un negativo si la HU no trae ninguno.
4. Si falta un Page Object: crearlo con acciones + `Locator`s, sin `expect`, `getByTestId` primero.
5. Si faltan datos: añadirlos a `data/<dominio>.data.ts` con `as const satisfies`.
6. Escribir `tests/ui/<feature>.spec.ts`: `beforeEach` solo navega, assertions web-first, sin sleeps, sin estado compartido.
7. Verificar: `npm run typecheck`, luego `npm run test:chromium -- tests/ui/<feature>.spec.ts`. Si el entorno no puede ejecutar, decirlo y dejar los comandos.
8. Entregar: archivos completos + 3 líneas (cubre / no cubre / asunciones).

## Qué entrega
- `tests/ui/<feature>.spec.ts` completo.
- Cambios en `pages/` y `data/` solo si fueron necesarios.
- Resultado del typecheck y del test, o los comandos pendientes.

## Prohibido
`waitForTimeout`, `expect` dentro de Page Objects, selectores CSS por clase, XPath, strings mágicos en el spec, `test.only`.
