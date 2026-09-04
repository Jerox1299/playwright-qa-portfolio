/**
 * Centralised SauceDemo credentials.
 *
 * Rationale: test data is a contract, not a literal scattered across specs. Keeping every account
 * in one typed module means a credential rotation is a one-line change, and each spec declares
 * WHICH persona it needs instead of hard-coding strings.
 */

/** SauceDemo uses one shared password for every demo account. */
export const SHARED_PASSWORD = 'secret_sauce';

export interface SauceUser {
  readonly username: string;
  readonly password: string;
  /** Why this persona exists in the suite: documents the risk each account is meant to cover. */
  readonly purpose: string;
}

export const USERS = {
  standard: {
    username: 'standard_user',
    password: SHARED_PASSWORD,
    purpose: 'Happy path: full access with no injected defects.',
  },
  lockedOut: {
    username: 'locked_out_user',
    password: SHARED_PASSWORD,
    purpose: 'Negative path: account disabled at authentication time.',
  },
  problem: {
    username: 'problem_user',
    password: SHARED_PASSWORD,
    purpose: 'Defect injection: broken images and inconsistent UI state.',
  },
  performanceGlitch: {
    username: 'performance_glitch_user',
    password: SHARED_PASSWORD,
    purpose: 'Latency injection: proves auto-waiting works without static sleeps.',
  },
  error: {
    username: 'error_user',
    password: SHARED_PASSWORD,
    purpose: 'Defect injection: failures during the checkout funnel.',
  },
  visual: {
    username: 'visual_user',
    password: SHARED_PASSWORD,
    purpose: 'Visual regression candidate: intentional layout drift.',
  },
} as const satisfies Record<string, SauceUser>;

export type UserKey = keyof typeof USERS;

/** Explicit empty credentials for required-field validation. */
export const EMPTY_CREDENTIALS: Pick<SauceUser, 'username' | 'password'> = {
  username: '',
  password: '',
};
