import http from 'k6/http';
import { check, group, sleep } from 'k6';
import { Rate, Trend } from 'k6/metrics';

/**
 * k6 load profile for the booking API.
 *
 * WHAT THIS MEASURES
 * Latency distribution and error rate of the read path under sustained concurrency. It answers a
 * question the functional suite cannot: not "does the endpoint work" but "does it still meet its
 * service level when twenty users hit it at once".
 *
 * WHY THE SCRIPT IS READ ONLY
 * A load profile that creates records leaves thousands of rows behind on every run. Against a
 * shared environment that is pollution, and against a public sandbox it is abuse. Write-path load
 * testing is legitimate, but it belongs in an environment you own and can reset.
 *
 * SAFETY GUARD
 * The default target is a public sandbox operated by someone else. Sustained load against
 * infrastructure you do not own, without written authorisation, is not a test: it is a denial of
 * service. The setup stage refuses to run the full profile against the default host unless the
 * operator opts in explicitly. Point BASE_URL at your own environment instead.
 */

const DEFAULT_PUBLIC_TARGET = 'https://restful-booker.herokuapp.com';
const BASE_URL = __ENV.BASE_URL || DEFAULT_PUBLIC_TARGET;
const SMOKE = String(__ENV.SMOKE || '').toLowerCase() === 'true';
const ALLOW_PUBLIC_TARGET = String(__ENV.ALLOW_PUBLIC_TARGET || '').toLowerCase() === 'true';

/** Full profile: ramp up, sustain, cool down. Smoke profile: one user, ten seconds. */
const LOAD_STAGES = [
  { duration: '30s', target: 20 }, // ramp up: 0 to 20 virtual users
  { duration: '1m', target: 20 },  // steady state: the window the percentiles are read from
  { duration: '15s', target: 0 },  // ramp down: lets in-flight requests finish cleanly
];

const SMOKE_STAGES = [{ duration: '10s', target: 1 }];

/** Contract failures are tracked apart from transport failures: a 200 can still carry a wrong body. */
const contractViolations = new Rate('contract_violations');
const listLatency = new Trend('list_endpoint_duration', true);
const detailLatency = new Trend('detail_endpoint_duration', true);

export const options = {
  stages: SMOKE ? SMOKE_STAGES : LOAD_STAGES,

  /**
   * Thresholds are the pass or fail criteria of the run. k6 exits non-zero when any of them
   * breaks, which is what makes this script a quality gate in a pipeline rather than a report
   * somebody has to read and interpret.
   */
  thresholds: {
    // The 95th percentile is the promise to almost every user; the 99th bounds the tail that
    // produces support tickets. An average would hide both.
    http_req_duration: ['p(95)<500', 'p(99)<1000'],

    // Less than one percent of requests may fail at transport level.
    http_req_failed: ['rate<0.01'],

    // A response can be fast, successful and still wrong. This gate covers correctness.
    contract_violations: ['rate<0.01'],
    checks: ['rate>0.99'],

    // Per-endpoint budgets: a slow detail endpoint must not hide behind a fast list endpoint
    // once both are averaged into the global metric.
    'http_req_duration{endpoint:list}': ['p(95)<500'],
    'http_req_duration{endpoint:detail}': ['p(95)<600'],
  },

  // Every request is tagged, so the summary can be sliced per endpoint.
  tags: { suite: 'booking-api-load' },

  // Abort early instead of burning the full profile when the target is already unhealthy.
  noConnectionReuse: false,
  userAgent: 'playwright-qa-portfolio-k6/1.0',
};

const JSON_HEADERS = {
  Accept: 'application/json',
  'Content-Type': 'application/json',
};

/** Parses a response body without letting a malformed payload abort the virtual user. */
function parseJsonSafely(response) {
  try {
    return response.json();
  } catch (_error) {
    return null;
  }
}

/**
 * Runs once before the ramp starts. Fails fast on an unreachable environment so the run does not
 * spend ninety seconds producing a wall of connection errors.
 */
export function setup() {
  if (BASE_URL === DEFAULT_PUBLIC_TARGET && !SMOKE && !ALLOW_PUBLIC_TARGET) {
    throw new Error(
      'Refusing to run the full load profile against the public sandbox. ' +
        'Point BASE_URL at an environment you own, or opt in explicitly with ' +
        '-e ALLOW_PUBLIC_TARGET=true, or run the smoke profile with -e SMOKE=true.',
    );
  }

  const health = http.get(`${BASE_URL}/ping`, { headers: JSON_HEADERS });

  if (health.status !== 201) {
    throw new Error(`Environment health check failed: ${BASE_URL}/ping returned ${health.status}`);
  }

  return { baseUrl: BASE_URL };
}

export default function (data) {
  const baseUrl = data.baseUrl;
  let sampledBookingId = null;

  group('GET /booking - collection', () => {
    const response = http.get(`${baseUrl}/booking`, {
      headers: JSON_HEADERS,
      tags: { endpoint: 'list' },
    });

    listLatency.add(response.timings.duration);

    const body = parseJsonSafely(response);
    const isArray = Array.isArray(body);

    const passed = check(response, {
      'list: status is 200': (r) => r.status === 200,
      'list: content type is json': (r) =>
        String(r.headers['Content-Type'] || '').includes('application/json'),
      'list: body parses as an array': () => isArray,
      'list: collection is not empty': () => isArray && body.length > 0,
      'list: every item exposes a numeric bookingid': () =>
        isArray && body.every((item) => item !== null && typeof item.bookingid === 'number'),
    });

    contractViolations.add(!passed);

    if (isArray && body.length > 0) {
      // Spread the detail requests across the collection instead of hammering one hot record,
      // which would be served from cache and report an unrealistically good latency.
      const index = Math.floor(Math.random() * Math.min(body.length, 100));
      sampledBookingId = body[index].bookingid;
    }
  });

  group('GET /booking/{id} - detail', () => {
    if (sampledBookingId === null) {
      return;
    }

    const response = http.get(`${baseUrl}/booking/${sampledBookingId}`, {
      headers: JSON_HEADERS,
      tags: { endpoint: 'detail' },
    });

    detailLatency.add(response.timings.duration);

    const body = parseJsonSafely(response);
    const isObject = body !== null && typeof body === 'object' && !Array.isArray(body);

    // 404 is a legitimate answer under concurrency: another client may have deleted the record
    // between the list call and this one. Treating it as a failure would manufacture flakiness.
    const found = response.status === 200;

    const passed = check(response, {
      'detail: status is 200 or 404': (r) => r.status === 200 || r.status === 404,
      'detail: content type is declared': (r) => String(r.headers['Content-Type'] || '') !== '',
      'detail: body is an object when found': () => !found || isObject,
      'detail: required fields are present when found': () =>
        !found ||
        (isObject &&
          typeof body.firstname === 'string' &&
          typeof body.lastname === 'string' &&
          typeof body.totalprice === 'number' &&
          typeof body.depositpaid === 'boolean'),
      'detail: booking dates are well formed when found': () =>
        !found ||
        (isObject &&
          body.bookingdates !== null &&
          typeof body.bookingdates === 'object' &&
          /^\d{4}-\d{2}-\d{2}$/.test(String(body.bookingdates.checkin))),
    });

    contractViolations.add(!passed);
  });

  // Think time. Without it twenty virtual users become a synthetic hammer that measures how fast
  // the server can be saturated, not how it behaves under a realistic arrival rate.
  sleep(1);
}

/**
 * Replaces the default end-of-run output. Writes a machine-readable summary for the pipeline to
 * archive and prints a compact human summary, with no remote import so the script also runs on an
 * isolated CI runner with no egress to a CDN.
 */
export function handleSummary(data) {
  const metric = (name) => (data.metrics && data.metrics[name]) || { values: {} };
  const duration = metric('http_req_duration').values;
  const failed = metric('http_req_failed').values;
  const checks = metric('checks').values;
  const requests = metric('http_reqs').values;

  const format = (value) => (typeof value === 'number' ? `${value.toFixed(2)} ms` : 'n/a');
  const percent = (value) => (typeof value === 'number' ? `${(value * 100).toFixed(2)} %` : 'n/a');

  const failedThresholds = [];
  for (const [name, values] of Object.entries(data.metrics || {})) {
    for (const [expression, result] of Object.entries(values.thresholds || {})) {
      if (result && result.ok === false) {
        failedThresholds.push(`${name}: ${expression}`);
      }
    }
  }

  const lines = [
    '',
    '  Booking API load profile',
    `    target            ${BASE_URL}`,
    `    profile           ${SMOKE ? 'smoke' : 'full ramp 0-20-0 VUs'}`,
    `    requests          ${requests.count ?? 'n/a'}`,
    `    median latency    ${format(duration.med)}`,
    `    p95 latency       ${format(duration['p(95)'])}`,
    `    p99 latency       ${format(duration['p(99)'])}`,
    `    max latency       ${format(duration.max)}`,
    `    request failures  ${percent(failed.rate)}`,
    `    checks passing    ${percent(checks.rate)}`,
    '',
    failedThresholds.length === 0
      ? '  All thresholds met.'
      : `  Thresholds breached:\n${failedThresholds.map((entry) => `    - ${entry}`).join('\n')}`,
    '',
  ];

  return {
    'performance/results/summary.json': JSON.stringify(data, null, 2),
    stdout: lines.join('\n'),
  };
}
