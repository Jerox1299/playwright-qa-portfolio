import { defineConfig, devices, type ReporterDescription } from '@playwright/test';
import { env } from './config/env';

/**
 * Playwright configuration - playwright-qa-portfolio
 *
 * Design goals:
 *  - Deterministic, fully isolated and parallel-safe tests (no shared state, no test ordering).
 *  - Zero static waits: rely on Playwright auto-waiting + web-first assertions.
 *  - Cheap-by-default failure evidence: heavy artifacts are produced ONLY when something fails.
 *  - One config that behaves differently on a developer laptop vs. CI, driven by env vars only.
 */

/** Single source of truth for the desktop viewport, applied on top of every device preset. */
const DESKTOP_VIEWPORT = { width: 1440, height: 900 } as const;

/** GitHub Actions (and most CI providers) set CI=true. Used to harden the run. */
const IS_CI = env.isCI;

/** Environment-driven URLs: the same suite can target dev/staging/prod without code changes. */
const UI_BASE_URL = env.uiBaseUrl;
const API_BASE_URL = env.apiBaseUrl;

/**
 * Reporters:
 *  - 'html'   -> self-contained report published as a CI artifact (open: 'never' so it does not
 *                block a headless pipeline by spawning a browser).
 *  - 'list'   -> readable live progress in the terminal / CI log.
 *  - 'github' -> CI only: annotates the failing line directly in the GitHub PR diff.
 */
const reporters: ReporterDescription[] = [
  ['html', { open: 'never', outputFolder: 'playwright-report' }],
  ['list'],
];
if (IS_CI) reporters.push(['github']);

export default defineConfig({
  /** Root of the suite; each project narrows this down to its own layer (ui / api). */
  testDir: './tests',

  /** Raw artifacts (traces, screenshots, videos) live here; the HTML report links to them. */
  outputDir: './test-results',

  /**
   * Run every test in parallel, including tests inside the same file.
   * This is a hard architectural constraint, not just a speed setting: it only works if tests
   * are fully independent (own user/session/data), which is exactly what we want to demonstrate.
   */
  fullyParallel: true,

  /** A committed test.only would silently shrink the suite in CI, so fail the build instead. */
  forbidOnly: IS_CI,

  /**
   * Retries only in CI. Locally 0 retries keeps flakiness visible instead of hiding it.
   * In CI, 2 retries absorb infrastructure noise while the HTML report still flags the test
   * as "flaky", so instability is reported rather than swallowed.
   */
  retries: IS_CI ? 2 : 0,

  /**
   * Workers: a fixed, conservative number on shared CI runners (predictable, avoids CPU
   * starvation and false timeouts); a percentage of local cores on a developer machine.
   */
  workers: IS_CI ? 2 : '50%',

  /** Per-test budget. Generous enough for a full E2E checkout, tight enough to catch hangs. */
  timeout: 60_000,

  expect: {
    /** Web-first assertion budget: expect() polls until this timeout before failing. */
    timeout: 10_000,
  },

  reporter: reporters,

  use: {
    baseURL: UI_BASE_URL,

    /**
     * Failure evidence strategy (cost vs. debuggability):
     *  - trace on the first retry: full timeline, DOM snapshots, network and console. This is the
     *    primary debugging tool and costs nothing on green runs.
     *  - screenshot only on failure: instant visual triage from the report.
     *  - video only retained on failure: the heaviest artifact, kept exclusively when it pays off.
     */
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',

    /** Bounded action/navigation budgets: fail fast with a clear cause instead of hitting the test timeout. */
    actionTimeout: 15_000,
    navigationTimeout: 30_000,

    /** SauceDemo exposes data-test attributes, so getByTestId() maps to the app's own contract. */
    testIdAttribute: 'data-test',

    viewport: DESKTOP_VIEWPORT,

    /** Headless by default everywhere; --headed is an explicit opt-in via npm script. */
    headless: true,
  },

  projects: [
    /**
     * UI layer: the same E2E suite executed against the three rendering engines Playwright
     * supports. Cross-engine coverage is the argument for Playwright over a single-engine tool.
     */
    {
      name: 'chromium',
      testDir: './tests/ui',
      use: { ...devices['Desktop Chrome'], viewport: DESKTOP_VIEWPORT },
    },
    {
      name: 'firefox',
      testDir: './tests/ui',
      use: { ...devices['Desktop Firefox'], viewport: DESKTOP_VIEWPORT },
    },
    {
      name: 'webkit',
      testDir: './tests/ui',
      use: { ...devices['Desktop Safari'], viewport: DESKTOP_VIEWPORT },
    },

    /**
     * API layer: isolated in its own project so contract tests run ONCE (not three times).
     * They need no browser, so browser-only artifacts are disabled to keep the run cheap.
     */
    {
      name: 'api',
      testDir: './tests/api',
      use: {
        baseURL: API_BASE_URL,
        /* Contract headers applied to every request of this project: the API negotiates JSON and
           restful-booker requires an explicit content type on write and delete operations. */
        extraHTTPHeaders: {
          Accept: 'application/json',
          'Content-Type': 'application/json',
        },
        trace: 'on-first-retry',
        screenshot: 'off',
        video: 'off',
      },
    },
  ],
});
