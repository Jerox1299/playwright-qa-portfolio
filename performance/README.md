# Performance testing with k6

Load profile for the booking API read path. It answers a question the functional suite cannot:
not *does the endpoint work*, but *does it still meet its service level when twenty users hit it
at the same time*.

---

## Installing k6

k6 is a single binary. It is not an npm package and it is deliberately kept out of
`package.json`: the functional suite must stay installable without dragging a load-testing
runtime into every developer machine and every CI job.

| Platform | Command |
| --- | --- |
| Windows | `winget install k6.k6` or `choco install k6` |
| macOS | `brew install k6` |
| Debian or Ubuntu | `sudo gpg -k && sudo apt-get install k6` after adding the Grafana repository |
| Any platform | `docker run --rm -i grafana/k6 run - < performance/load-test.js` |

Verify the install with `k6 version`.

---

## Running the profile

```bash
# Smoke profile: one virtual user, ten seconds. Use this to prove the script works.
k6 run -e SMOKE=true performance/load-test.js

# Full profile against an environment you own.
k6 run -e BASE_URL=https://booking.your-staging-env.internal performance/load-test.js

# Full profile against the public sandbox: requires an explicit opt-in.
k6 run -e ALLOW_PUBLIC_TARGET=true performance/load-test.js
```

The script refuses to run the full ramp against the default public sandbox unless you opt in.
Sustained load against infrastructure you do not own, without written authorisation, is not a
test. It is a denial of service. Point `BASE_URL` at your own environment.

### Load stages

| Phase | Duration | Virtual users | Purpose |
| --- | --- | --- | --- |
| Ramp up | 30 s | 0 to 20 | Reveals whether the system degrades gradually or falls off a cliff |
| Steady state | 1 min | 20 | The only window whose percentiles are meaningful |
| Ramp down | 15 s | 20 to 0 | Lets in-flight requests finish so the tail is not truncated |

### Output

The run writes `performance/results/summary.json` for the pipeline to archive, and prints a
compact human summary. The results directory is git-ignored: metrics belong to a run, not to the
repository. k6 exits non-zero when any threshold breaks, which is what turns this script into a
quality gate rather than a report somebody has to read and interpret.

---

## Reading the metrics

**Percentiles, not averages.** An average is the one statistic that describes nobody. If ninety
requests return in 100 ms and ten return in 5 s, the average is 590 ms: a number no user ever
experienced, and one that hides the ten people who waited five seconds. The 95th percentile is
the promise made to almost everyone. The 99th percentile bounds the tail that generates support
tickets. Both are asserted here, and the average is not asserted at all.

**The thresholds and what breaking them means.**

| Threshold | Meaning when it breaks |
| --- | --- |
| `http_req_duration: p(95)<500` | One in twenty users is waiting longer than half a second |
| `http_req_duration: p(99)<1000` | The tail is out of control even if the median looks healthy |
| `http_req_failed: rate<0.01` | More than one percent of requests failed at transport level |
| `contract_violations: rate<0.01` | Responses arrived fast and with status 200 but the payload was wrong |
| `checks: rate>0.99` | Aggregate correctness of every assertion in the script |
| `http_req_duration{endpoint:detail}` | Per-endpoint budget, so a slow endpoint cannot hide behind a fast one |

**Why per-endpoint thresholds matter.** A global percentile mixes a cheap list endpoint with an
expensive detail endpoint. If the cheap one dominates the request count, the expensive one can
degrade badly while the global number stays green. Tagging each request and asserting per tag is
what keeps that from happening.

**Calibrating the numbers.** The thresholds in this script are the service levels of a system you
control. Run against the public sandbox, hosted on shared infrastructure with cold starts, they
will very likely breach: a single cold request measured around 590 ms during verification. That
breach is correct behaviour from the tool. A threshold that always passes is decoration, and the
first job when adopting this script on a real system is to set the numbers from the actual
service level objective rather than from the defaults here.

---

## Why k6 and Playwright do not mix

Both suites live in this repository and neither imports the other. That separation is deliberate.

**They measure different things.** Playwright measures whether behaviour is correct for one user.
k6 measures whether performance holds for many users at once. The API suite in `tests/api/` does
assert response times, but those assertions are explicitly labelled as smoke budgets: they catch
an endpoint that has degraded from milliseconds to seconds. They say nothing about behaviour
under concurrency, because a single sequential request cannot.

**A browser is the wrong instrument for load.** Playwright drives real browser engines. Each one
costs hundreds of megabytes of memory, so a single machine runs a handful of them, and most of
the latency measured is rendering rather than server time. k6 has no browser and no DOM: one
machine sustains thousands of virtual users, and every millisecond it reports is server time.

**Statistical models differ.** A functional test is a binary outcome, pass or fail, and it retries
on failure to absorb infrastructure noise. A performance test is a distribution: retrying a slow
request would erase the very signal being measured. Mixing them means either the functional suite
inherits flaky timing assertions, or the performance suite inherits retries that falsify its
percentiles.

**Different failure semantics in the pipeline.** A functional failure blocks the merge. A
performance threshold breach is often a warning that needs a trend across runs before anyone acts
on it. Keeping them in separate jobs lets each one fail on its own terms.

**Where each one runs.** The functional suite runs on every push and pull request, in minutes.
The load profile runs on a schedule or before a release, against a dedicated environment, because
its results are meaningless on a runner that is simultaneously executing browser tests.
