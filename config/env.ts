/**
 * Typed resolution of the test environment.
 *
 * Why this module exists: reading process.env inline scatters string literals and silent fallbacks
 * across the suite. A misspelled or malformed variable then surfaces much later as a confusing test
 * failure -- a 404 against the wrong host, a suite that "passes" against the default target instead
 * of the one that was requested. Resolving here means an invalid environment fails once, at load
 * time, with a message that names the offending variable.
 *
 * Secrets are never read from a file in this repository. Locally they come from the operating
 * system credential manager, injected as environment variables; in CI they come from GitHub Actions
 * Secrets. Nothing in this module reads or writes a .env file, by design.
 */

/** Public sandboxes used when no target is supplied. Both are safe to hit from a laptop. */
const DEFAULT_URLS = {
  UI_BASE_URL: 'https://www.saucedemo.com',
  API_BASE_URL: 'https://restful-booker.herokuapp.com',
} as const;

type UrlVariable = keyof typeof DEFAULT_URLS;

/**
 * Resolves one URL variable, falling back to its documented default.
 *
 * Validation is deliberate rather than defensive: an unset variable is a normal case and gets the
 * default, but a variable that IS set and malformed is an operator mistake, and failing loudly is
 * cheaper than debugging a suite pointed at nothing.
 */
function resolveUrl(name: UrlVariable): string {
  const raw = process.env[name]?.trim();

  if (raw === undefined || raw === '') {
    return DEFAULT_URLS[name];
  }

  let parsed: URL;
  try {
    parsed = new URL(raw);
  } catch {
    throw new Error(
      `${name} is not a valid absolute URL. Received "${raw}". Expected something like https://staging.example.com`,
    );
  }

  if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
    throw new Error(`${name} must use http or https. Received protocol "${parsed.protocol}" in "${raw}".`);
  }

  // Trailing slashes are stripped because Playwright joins baseURL with paths such as
  // '/inventory.html', and the resulting double slash makes some servers answer 404.
  return raw.replace(/\/+$/, '');
}

/**
 * Reads a boolean flag with the same semantics the previous inline check had: any non-empty value
 * means true, except the two spellings that explicitly mean false. CI providers are inconsistent
 * here -- GitHub Actions sets CI=true, others set CI=1 -- so the check tolerates all of them
 * instead of hard-coding one provider's convention.
 */
function resolveFlag(name: string): boolean {
  const raw = process.env[name]?.trim().toLowerCase();

  if (raw === undefined || raw === '') {
    return false;
  }

  return raw !== 'false' && raw !== '0';
}

export interface TestEnvironment {
  /** Base URL of the application under test for the UI projects. */
  readonly uiBaseUrl: string;
  /** Base URL of the API under test for the api project. */
  readonly apiBaseUrl: string;
  /** True when running on a continuous integration runner. Drives retries, workers and forbidOnly. */
  readonly isCI: boolean;
}

/** Frozen so a spec cannot mutate the environment other tests are running against. */
export const env: TestEnvironment = Object.freeze({
  uiBaseUrl: resolveUrl('UI_BASE_URL'),
  apiBaseUrl: resolveUrl('API_BASE_URL'),
  isCI: resolveFlag('CI'),
});
