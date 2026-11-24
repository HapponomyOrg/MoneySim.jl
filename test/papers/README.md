# Paper-based regression suite

This directory holds the before/after test suite for the WASM-ready refactor.
The papers under `jupyter/` are the external oracle; a captured legacy baseline
is the internal oracle.

The full design is in the
[`sim.wasm` plan](https://github.com/HapponomyOrg/sim.wasm/blob/main/docs/plans/2026-10-21-wasm-ready-core.md),
§9.

## Why

The refactor changes the money representation, the RNG, the config shape, and
possibly the rounding. Structural tests alone cannot tell us whether the
economics still behave. The suite compares the same scenario manifest through
two backends:

- `backend = :legacy` — the pre-refactor `MoneySim` implementation;
- `backend = :core` — `MoneySimCore`.

Paper 1 and paper 2 are captured at their paper parameters. Paper 3 is captured
at a reduced scale (default 1,000 actors × 10 years) so the live legacy capture
stays practical; the scale is recorded in the baseline metadata.

## Workflow

```bash
# 1. Capture the legacy baseline (before the refactor / after a manifest change)
PAPER_TESTS=write julia --project=. test/papers/run.jl

# 2. PR suite: legacy paper checks + core-vs-baseline comparison
PAPER_TESTS=fast julia --project=. test/papers/run.jl

# 3. Full suite: also runs every legacy paper-2 equilibrium
PAPER_TESTS=full julia --project=. test/papers/run.jl

# 4. Seed sweep: compare the mean over several seeds per backend
PAPER_TESTS=seeds PAPER_SEEDS=5 julia --project=. test/papers/run.jl

# or add the sweep to the PR suite
PAPER_SEEDS=5 PAPER_TESTS=fast julia --project=. test/papers/run.jl
```

`write` takes roughly 4–6 minutes (paper 2 dominates). Paper 3 can be captured
at the paper scale for a nightly run:

```bash
PAPER3_BASELINE_ACTORS=10000 PAPER3_BASELINE_YEARS=100 \
  PAPER_TESTS=write julia --project=. test/papers/run.jl
```

The core comparison reads the actor/year scale back from
`fixtures/baseline.toml`, so it always uses the same scale as the captured
legacy run.

## Files

| File | Purpose |
|---|---|
| `scenarios.jl` | Canonical, data-only scenario manifest for papers 1–3 |
| `adapter.jl` | `run_paper1/2/3(...; backend = :legacy/:core)` |
| `compare.jl` | Tolerance-aware before/after comparison |
| `capture_baseline.jl` | Writes `fixtures/baseline.toml` from the legacy backend |
| `fixtures/baseline.toml` | Captured legacy numbers + metadata |
| `paper1.jl` | Exact closed-form assertions from the paper 1 notebook |
| `paper2.jl` | SUMSY scenarios, bounds, consumer–supplier balances |
| `paper3.jl` | Fixture integrity (238 checks) |
| `seeds.jl` | Multi-seed paper-3 mean comparison (`PAPER_SEEDS`) |
| `run.jl` | Entry point; honours `PAPER_TESTS` and `PAPER_SEEDS` |

## Paper 1 note

The paper runs `M0 = 1,000,000`. The core comparison uses `M0 = 10,000` because
the ratios are scale-invariant and scaled Int64 cannot represent the paper's
`loan_rate_stable_m30` trajectory (it reaches ~10²⁶ currency). Every
representable scenario is compared on debt ratio, growth ratio, and length;
`loan_rate_stable_m30` is reported as skipped. The same Int64 limit is why the
paper-1 random-growth series saturate instead of growing indefinitely.

Int128 would represent that trajectory but would not remove any other delta:
the remaining paper-3 gaps are stochastic/ordering differences, not
representation. It is also not wasm-native (the ABI and JS bindings are i64),
so it would split the native and wasm backends.

## Parity status

At the committed comparison scale (1,000 actors × 10 years), with legacy and
core both run at seed 42, the largest deltas are:

| Metric | Max delta |
|---|---|
| Money stock / public debt | 0.25% |
| Tax collected | 1.35% (`a9`); 0.77% (`a10`) |
| Gini wealth | 0.029 (`c4`) |
| Gini income | 0.017 |
| Wealth / income shares | 2.2 pp |
| Tax scale | 0.02 |

Four deterministic discrepancies were fixed to get there:

1. the Belgian income-tax schedule was missing the 0% band up to €10,190, so
   core taxed the first bracket at 25%;
2. the bottom percentile groups were not overlap-adjusted, unlike legacy
   (`bottom_10` changes from −768 to +3,868);
3. the first VAT window did not include projected/notional income, which legacy
   includes via `init_income!` (this showed up as a year-2 tax and money-stock
   gap in `c1`);
4. scenario `a10` was missing `cover_expenses = true`, the legacy default for
   demurrage tax. Legacy recorded a 0.96 downscale but only applies scaling when
   revenue is *below* target, so the missing flag showed up as a 3% tax gap.
   With the flag, `a10` matches the paper to 0.001% at 10k actors and is stable
   at −0.77% vs legacy across seeds.

The multi-seed sweep confirms the remainder is RNG noise: with 10 seeds the
mean Gini delta is ≤0.003 for almost every scenario; the largest are `u1`
(+0.009) and `c4` (+0.004). The 5-seed run's `c4`/`u1` outliers (+0.016/+0.019)
were sampling error.

## Multi-seed comparison

The legacy backend uses Julia's global `MersenneTwister`; the core uses an
explicit xorshift64 passed through every call. The streams (and even the number
of draws) differ, so a single paper-3 seed can look worse than the underlying
model parity. `PAPER_TESTS=seeds` runs both backends for seeds `1:N` and compares
the mean outcome with tighter tolerances than the single-seed check.

This is not "common random numbers": making the streams identical would require
rewriting the legacy global `rand()` use and matching core draw order, and would
not reflect what runs in wasm. Multi-seed is the more robust check.

## Paper 3 tolerances

The legacy and core RNG streams differ, so paper-3 levels are distribution
checks, not trace checks:

| Comparison | SUMSY scenarios | Fixed-money scenarios |
|---|---|---|
| Gini wealth / income | ±0.06 | ±0.15 |
| Tax scale | ±0.35 | ±0.40 |
| Percentile shares | ±7 pp | ±8 pp |
| Money stock | ±2% | ±2% |
| Public debt | ±2% | ±2% |
| Tax collected | ±1.5% | ±1.5% |

Money, debt, and collected tax are the strict invariants. Direction checks
(`a2 < a1`, `a3 < a1`, `b1 > a1`, `c3.scale > c2.scale`) are release-blocking.
At the paper scale (10,000 actors × 100 years) the SUMSY distributions converge
close to the committed fixtures; the fixed-money c-series is chaotic across RNG
streams.

## Dependencies

`MoneySimCore` and `EconoSimCore` are workspace sources in `Project.toml`:

```toml
[sources]
EconoSimCore = {path = "../EconoSim.jl/core"}
MoneySimCore = {path = "core"}
```

This is a workspace-only source; published packages will use git URLs or
registry versions.

## Paper 3 fixtures

Use only the aggregate CSVs:

```
jupyter/paper 3/data/<scenario>/gini_wealth.csv
jupyter/paper 3/data/<scenario>/gini_income.csv
jupyter/paper 3/data/<scenario>/money_stock.csv
jupyter/paper 3/data/<scenario>/percentile_wealth_data.csv
jupyter/paper 3/data/<scenario>/percentile_income_data.csv
jupyter/paper 3/data/<scenario>/model_data.csv
```

**Do not load `actor_data.csv`.** For `b1` and `c1` it is 64–86 MB and is not
needed for the aggregate checks.

## Adding a scenario

1. Add an entry to `scenarios.jl` with `kind`, `params`, `expected`, and
   `fixture` (if it has a committed CSV).
2. Add any scenario-specific assertion to the matching `paperN.jl`.
3. Re-run `PAPER_TESTS=write` to refresh the baseline.

Keep the manifest declarative: no simulation calls, no imports from `MoneySim`
or `MoneySimCore`.
