# Playwright QA Portfolio

Senior QA Automation portfolio: end-to-end UI and API testing with Playwright + TypeScript,
built to demonstrate production-grade test architecture rather than tutorial-level scripting.

[![CI](https://github.com/REPLACE_ME/playwright-qa-portfolio/actions/workflows/ci.yml/badge.svg)](https://github.com/REPLACE_ME/playwright-qa-portfolio/actions/workflows/ci.yml)

## Stack

- **Playwright + TypeScript** (strict mode) for UI and API testing
- **Page Object Model** — page objects expose behaviour and state only; assertions live in specs
- **Data factories** — tests build their own data instead of sharing mutable fixtures, so every
  test is independent and safe to run fully in parallel
- **GitHub Actions** — matrix run across Chromium, Firefox, WebKit and the API project on every
  push and pull request

## Systems under test

- UI: [saucedemo.com](https://www.saucedemo.com) — login and checkout flows
- API: [restful-booker](https://restful-booker.herokuapp.com) — CRUD and JSON schema validation

Both are public demo services, chosen so the suite runs against a real, stable target with no
credentials or infrastructure to provision.

## Architecture decisions

- **No static waits.** The suite relies entirely on Playwright's auto-waiting and web-first
  (`expect(locator)...`) assertions — no `waitForTimeout`, no manual polling.
- **No assertions inside page objects.** A page object returns `Locator`s, not booleans or
  strings; the spec decides what "correct" means and asserts it. This keeps the requirement
  readable in the test itself.
- **No raw CSS/XPath selectors.** Locators are built from Playwright's role/text/test-id APIs so
  they read like user intent and survive markup churn.
- **Fully parallel by design.** Every test builds its own data via a factory (see `data/`)
  instead of mutating shared state, which is what makes safe parallel execution possible.
- **CI-only retries.** 0 retries locally (flakiness stays visible while developing), 2 retries in
  CI (absorbs infra noise while the HTML report still flags a test as flaky instead of hiding it).

## Project structure

```
pages/     Page objects (behaviour + locators, no assertions)
data/      Data factories used by both UI and API tests
tests/ui/  End-to-end UI specs
tests/api/ API specs + a small typed HTTP client and JSON-schema contracts
```

## Running locally

```bash
npm ci
npx playwright install --with-deps
npm run typecheck
npm run test:ui     # UI suite only
npm run test:api    # API suite only
npm test            # everything
npm run report      # open the last HTML report
```

## Roadmap

Scaffolded but not yet implemented — listed here rather than left as unexplained empty folders:

- `sql/` — direct database assertions against the seed/test data layer
- `performance/` — k6 load-testing scenarios for the checkout flow
