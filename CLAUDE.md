# playwright-qa-portfolio

## Qué es
Portafolio de QA Automation senior: E2E (SauceDemo) y API (restful-booker) con Playwright + TypeScript estricto, validaciones SQL en PostgreSQL, carga con k6 y CI en GitHub Actions.

## Stack
- Runtime: Node >= 22, TypeScript 7 (`strict`, `noUncheckedIndexedAccess`, `noUnusedLocals`)
- Test runner: @playwright/test 1.62 (proyectos: chromium, firefox, webkit, api)
- Path aliases: `@pages/*` -> `pages/`, `@data/*` -> `data/`
- SQL: PostgreSQL (`sql/`), ejecutable con psql o Docker
- Performance: k6 (`performance/`)
- CI: `.github/workflows/playwright.yml` (typecheck -> install browsers -> `npm test`)

## Estructura
```
pages/        Page Objects (una clase por pantalla)
data/         Test data tipada (usuarios, productos, payloads)
tests/ui/     Specs E2E, se ejecutan en 3 engines
tests/api/    Specs de contrato/CRUD + support/ (plumbing sin asserts)
config/       Resolución tipada de entorno (env.ts)
sql/          Schema + seed con defectos plantados y 10 queries de validación
performance/  Script k6 y resultados
.claude/      prompts/, skills/, agents/ para trabajar con Claude Code
```

## Reglas duras (no negociables)
1. Page Objects exponen acciones y `Locator`s. Nunca contienen `expect`. Nunca devuelven otro Page Object.
2. Assertions solo en el spec, siempre web-first (`await expect(locator).toX()`). Nunca `expect(await locator.textContent())`.
3. Prohibido `page.waitForTimeout`, `sleep`, o polling manual. Usa auto-wait y `expect` con timeout.
4. Locators: `getByTestId` (data-test) primero, luego `getByRole`. Nunca CSS por clase ni XPath.
5. Cada test es independiente: crea su propio estado, no depende de orden ni de otro test. `fullyParallel` es un contrato.
6. `tests/api/support/` es plumbing: lanza `throw`, no `expect`. Un precondition roto es error de infra, no defecto del producto.
7. Test data vive en `data/*.data.ts` tipada con `as const satisfies`. Nunca strings mágicos en specs.
8. Secretos: nunca en el repo ni en `.env` con valores reales. Local -> gestor del SO (Windows Credential Manager) inyectado como variable de entorno; CI -> GitHub Actions Secrets. Ver `config/env.ts`.
9. Commits: Conventional Commits (`feat:`, `fix:`, `test:`, `chore:`, `docs:`). Nunca `--no-verify` ni `--force` sobre `main`.
10. Nunca `git add .` a ciegas: agrega archivos por nombre.
11. Nada de `test.only` commiteado (`forbidOnly` en CI lo rompe).
12. Comentarios explican el POR QUÉ de una decisión, no el QUÉ hace el código.

## Comandos
```
npm run typecheck          # gate de tipos, corre antes que cualquier suite
npm test                   # suite completa (4 proyectos)
npm run test:ui            # solo E2E
npm run test:api           # solo API
npm run test:chromium      # E2E en un engine, para iterar rápido
npm run test:debug         # inspector de Playwright
npm run report             # abrir último HTML report
```
En esta máquina (Windows) los binarios nativos de node_modules solo corren en Windows: ejecutar typecheck y tests desde la terminal de VS Code, no desde entornos Linux montados.

## Flujo de trabajo con Claude Code
- Tarea chica y reversible -> auto mode. Cruza varios archivos -> plan mode primero.
- 1 tarea = 1 sesión. Al terminar: `/clear`. Contexto > 70% -> cerrar tarea y abrir sesión nueva.
- Nueva feature: skill `gen-e2e-spec` (spec desde historia de usuario). Nuevo dataset SQL: skill `gen-test-data`.
- Trabajo paralelo: agentes `e2e-tester` y `api-tester` en `.claude/agents/`.
- Toda entrega termina con `npm run typecheck` verde y la suite afectada verde.

## Definition of Done para un spec nuevo
- Nombre del test lee como requisito ("a standard user signs in and lands on the product catalogue").
- Al menos un camino feliz y un camino negativo.
- Sin sleeps, sin selectores frágiles, sin estado compartido.
- Datos nuevos añadidos a `data/`, no inline.
- Pasa en chromium localmente y typecheck verde.
