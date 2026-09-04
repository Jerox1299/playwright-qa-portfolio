# Playwright QA Portfolio

[![Playwright Tests](https://github.com/Jerox1299/playwright-qa-portfolio/actions/workflows/playwright.yml/badge.svg)](https://github.com/Jerox1299/playwright-qa-portfolio/actions/workflows/playwright.yml)
[![Node](https://img.shields.io/badge/node-%3E%3D22-339933?logo=node.js&logoColor=white)](https://nodejs.org)
[![Playwright](https://img.shields.io/badge/Playwright-1.62-2EAD33?logo=playwright&logoColor=white)](https://playwright.dev)
[![TypeScript](https://img.shields.io/badge/TypeScript-strict-3178C6?logo=typescript&logoColor=white)](https://www.typescriptlang.org)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A test automation architecture built the way a quality engineering function is actually built:
four layers that answer four different questions, each one deliberately kept separate from the
others.

| Layer | Question it answers | Tooling |
| --- | --- | --- |
| End to end | Can a user complete the journey in every browser engine? | Playwright, Page Object Model |
| API contract | Is the payload still shaped the way every consumer expects? | Playwright `APIRequestContext` |
| Data validation | Do the orders and the payment ledger agree once the interface is out of the picture? | SQL, window functions |
| Performance | Does the service level hold when many users arrive at once? | k6 |

The storefront can be green while the payment ledger is wrong. That gap is why the SQL layer
exists. A response can be fast, return 200 and still carry the wrong body. That gap is why the contract
layer exists. Each layer covers a class of defect the layer above it structurally cannot see.

---

## What is in the suite

| Metric | Value |
| --- | --- |
| End-to-end test cases | 5, executed across Chromium, Firefox and WebKit |
| API test cases | 6, executed once, without a browser |
| Total tests per full run | 21 |
| Page objects | 4 |
| SQL validation checks | 10 |
| Static waits anywhere in the repository | 0 |

---

## Project structure

```
playwright-qa-portfolio/
├── .github/workflows/
│   └── playwright.yml           CI pipeline: type gate, suite, report and trace artifacts
├── pages/                       Page Object Model. Exposes behaviour and state, never assertions
│   ├── LoginPage.ts
│   ├── InventoryPage.ts
│   ├── CartPage.ts
│   └── CheckoutPage.ts
├── tests/
│   ├── ui/                      End-to-end journeys against saucedemo.com
│   │   ├── login.spec.ts        Happy path, locked account, required-field validation
│   │   └── checkout.spec.ts     Full purchase flow plus checkout validation
│   └── api/                     Contract tests against restful-booker
│       ├── booking-crud.spec.ts     Chained lifecycle: auth, create, read, update, delete, verify
│       ├── schema-validation.spec.ts Contract, headers, latency budgets, negative cases
│       └── support/
│           ├── schema.ts        Hand-written JSON contract validator, zero dependencies
│           ├── contracts.ts     The shapes the API promises, in one place
│           └── booking.api.ts   Auth and teardown helpers. No assertions live here
├── data/                        Test data and factories. One unique record per test
│   ├── users.data.ts
│   ├── products.data.ts
│   ├── checkout.data.ts
│   └── booking.data.ts
├── sql/                         Data validation for the orders and payments domain
│   ├── database-validations.sql Ten checks, each documenting its risk and technique
│   └── schema-and-seed.sql      Schema plus a dataset with deliberately planted defects
├── performance/                 Load profile, kept out of the functional suite on purpose
│   ├── load-test.js             k6 ramp profile with strict thresholds
│   └── README.md                Metric interpretation and why k6 does not mix with Playwright
├── playwright.config.ts         Multi-browser projects, artifacts, retries, reporters
├── tsconfig.json                Strict TypeScript, used as a gate and never to emit
├── package.json                 Scripts and pinned devDependencies
├── .gitignore                   Excludes node_modules, reports, traces and k6 results
└── LICENSE                      MIT
```

---

## Key technical decisions

**Page objects expose locators, not resolved strings.** Every query method returns a `Locator`
rather than text. A locator is lazy, so the spec wraps it in a web-first assertion that retries
until it passes. Returning already-resolved text would freeze the DOM at an arbitrary instant and
reintroduce the race condition that auto-waiting exists to remove.

**Assertions live in specs, never in page objects.** A page object that asserts hides the
requirement inside the plumbing. Reading a spec should tell you what the system must do without
opening a second file.

**Page objects never return other page objects.** Navigation changes the URL and the spec decides
which page it talks to next. This keeps the dependency graph acyclic and stops a reader from
having to trace three classes to understand one test.

**Full parallelism as an architectural constraint.** `fullyParallel` is enabled, including tests
within the same file. It is not a speed setting: it fails immediately if any test depends on
another's state. Every test builds its own data, so two tests running at once can never assert
against the same record.

**Failure evidence priced by usefulness.** Traces are captured on the first retry, giving a full
timeline with DOM snapshots, network and console at zero cost on green runs. Screenshots are kept
only on failure. Video is the heaviest artifact and is retained only on failure, since it largely
duplicates what the trace already shows.

**Retries only in CI.** Locally there are zero retries so instability stays visible the moment it
is introduced. In CI two retries absorb infrastructure noise while the report still marks the test
as flaky, so the instability is reported rather than swallowed.

**API tests run once, not three times.** Contract tests sit in their own project with no browser.
Running them against three rendering engines would triple the cost and produce no new information.

**Ephemeral data with idempotent teardown.** Each API test generates a uniquely identified payload,
creates its record and removes it in a `finally` block, so an aborted run leaves nothing behind.
Cleanup accepts the responses that mean "already gone", because a teardown that fails on a missing
record is a teardown that turns one red test into two.

**Contract validation with zero extra dependencies.** The JSON schema validator is roughly forty
lines written by hand. It covers required keys, field types, nested objects and undeclared keys.
A schema library would have been a dependency added to a test framework for a handful of
assertions, and every dependency there is a supply-chain and maintenance cost.

**Locators follow the application's own contract.** `testIdAttribute` is configured as `data-test`,
which is the attribute the application under test publishes. Where no test id exists, elements are
resolved by ARIA role and accessible name, so tests survive changes to generated identifiers.

---

## Running locally

Requires Node 22 or newer.

```bash
npm ci                      # install exactly what the lockfile pins
npm run install:browsers    # download Chromium, Firefox and WebKit
```

### Test execution

```bash
npm test                    # everything: 3 browsers plus the API project
npm run test:ui             # end-to-end only
npm run test:api            # API contract only, single execution
npm run test:headed         # Chromium with a visible window
npm run test:debug          # step through with the Playwright Inspector
npm run test:chromium       # single engine, fastest local feedback
npm run report              # open the last HTML report
npm run typecheck           # strict type gate, no tests executed
npm run codegen             # record a new flow against the application
```

### SQL validations

```bash
createdb qa_sandbox
psql -d qa_sandbox -f sql/schema-and-seed.sql        # schema plus planted defects
psql -d qa_sandbox -f sql/database-validations.sql   # the ten checks
```

Eight of the ten checks are assertions where an empty result set means pass and every returned row
is a defect report. The remaining two are reports, and their headers say so. The seed file exists
so any reviewer can confirm each check detects the anomaly it claims, and equally that it leaves
the healthy control rows alone.

### Performance

```bash
k6 run -e SMOKE=true performance/load-test.js                       # one user, ten seconds
k6 run -e BASE_URL=https://your-own-environment performance/load-test.js
```

The script refuses to run the full ramp against the public sandbox unless you opt in explicitly.
Sustained load against infrastructure you do not own, without written authorisation, is not a
test. See [performance/README.md](performance/README.md) for metric interpretation.

---

## CI/CD strategy

The pipeline runs on every push and pull request to the trunk, on `ubuntu-latest`, headless.

**The type gate runs before the browsers.** `npm run typecheck` executes before any browser is
downloaded. A type error is deterministic and surfaces in seconds, so paying for browser installs
and a full suite before discovering it would be wasted runner time.

**Dependencies install from the lockfile.** `npm ci` fails when the lockfile and the manifest have
drifted, instead of silently resolving a tree nobody reviewed.

**The environment configures the run, not a code change.** `playwright.config.ts` keys off the `CI`
variable that GitHub sets automatically, switching on retries, forbidding a committed `test.only`,
fixing the worker count for a two-core runner and adding the reporter that annotates failures
directly in the pull request diff.

**Evidence is published even when the suite fails.** Both upload steps use `always()`. A red
pipeline with no artifacts attached forces every engineer to reproduce the failure locally before
they can begin diagnosing it. The HTML report and the trace directory are retained for thirty days,
long enough to investigate a regression found late in a sprint.

**Superseded runs are cancelled.** A pipeline still executing for an outdated commit answers a
question nobody is asking.

**The load profile is not in this pipeline, deliberately.** Performance results measured on a
runner that is simultaneously executing browser tests are noise. k6 belongs on a schedule or a
pre-release gate, against a dedicated environment.

---

## License

MIT. See [LICENSE](LICENSE).
