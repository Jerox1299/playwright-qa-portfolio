# Prompt · Generar spec E2E desde una historia de usuario

Estructura de 7 partes (rol, contexto, tarea, restricciones, formato, ejemplo, criterio de éxito).
Copia el bloque, rellena `<...>` y pégalo en Claude Code dentro de este repo.

---

**Rol.** Eres un SDET senior especializado en Playwright + TypeScript estricto y Page Object Model.

**Contexto.** Trabajas en `playwright-qa-portfolio`. Lee `CLAUDE.md` para las reglas duras. Page Objects existentes: `pages/LoginPage.ts`, `pages/InventoryPage.ts`, `pages/CartPage.ts`, `pages/CheckoutPage.ts`. Test data en `data/*.data.ts`. Specs de referencia: `tests/ui/login.spec.ts`, `tests/ui/checkout.spec.ts`.

**Tarea.** Implementa la cobertura E2E para esta historia de usuario:

```
Como <persona>
quiero <acción>
para <resultado>

Criterios de aceptación:
- <AC1>
- <AC2>
- <AC3>
```

**Restricciones.**
- Un test por criterio de aceptación, más al menos un camino negativo aunque la HU no lo mencione.
- Reutiliza Page Objects existentes; si falta uno, créalo siguiendo exactamente el estilo de `LoginPage.ts` (acciones + Locators, sin `expect`).
- Nuevos datos van a `data/`, tipados con `as const satisfies`.
- Cero `waitForTimeout`; solo assertions web-first.
- Nombres de test en inglés que se lean como requisito.

**Formato de salida.** Archivos completos, no fragmentos: `tests/ui/<feature>.spec.ts`, cambios en `pages/` y `data/` si aplican. Al final, una lista de 3 líneas: qué cubre, qué NO cubre, qué asumiste de la app.

**Ejemplo de test esperado.**
```ts
test('a standard user removes an item and the cart badge updates', async ({ page }) => {
  const inventoryPage = new InventoryPage(page);
  await inventoryPage.addToCart(PRODUCTS.backpack.id);
  await inventoryPage.removeFromCart(PRODUCTS.backpack.id);
  await expect(inventoryPage.getCartBadge()).toBeHidden();
});
```

**Criterio de éxito.** `npm run typecheck` verde y `npm run test:chromium -- tests/ui/<feature>.spec.ts` verde. Si no puedes ejecutarlo, dilo explícitamente y deja el comando listo.
