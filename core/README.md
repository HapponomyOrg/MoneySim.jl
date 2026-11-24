# MoneySimCore

Dependency-free simulation core for MoneySim. It depends only on
`EconoSimCore`; there are no Agents.jl, DataFrames, plotting, or wasm tooling
dependencies.

This is Phase 4a of the wasm-ready core plan. The canonical plan lives in
`sim.wasm/docs/plans/2026-10-21-wasm-ready-core.md`.

## What is here

| File | Contents |
|---|---|
| `src/types.jl` | `SimConfig`, `MoneyConfig`, `TransactionConfig`, `TaxConfig`, `VatConfig`, `WealthConfig`, `PopulationConfig`, `GovernmentConfig`, `GdpConfig`, `AdaptationConfig`, `BankConfig`, `LoanCircuitConfig` |
| `src/state.jl` | `SimState` (structure-of-arrays), `ResultBuffers`, `SimResult` |
| `src/metrics.jl` | Gini, mean/total/min/max, cumulative percentile shares, income Gini, tax scale, public debt, VAT, loan-circuit series |
| `src/transactions.jl` | Yard-sale transactions, the GDP volume target, and the paper-2 consumer–supplier model |
| `src/taxes.jl` | Wealth levy, progressive income tax and demurrage tax with legacy target scaling, VAT, all four recipient modes |
| `src/money_models.jl` | Fixed money, SUMSY (GI + demurrage, settlement granularity, typed GI), homogeneous debt-based interest, post-Keynesian bank, paper-1 loan circuit (fixed and random growth/loan-rate modes) |
| `src/population.jl` | Fixed population, births/deaths/aging, typed GI eligibility, initial age shares |
| `src/adaptations.jl` | Money injection and destruction (total, per-actor, one-time, half-balance) and equal distribution |
| `src/countries.jl` | Typed country datasets, Belgium 2023, unequal-wealth and unequal-income distribution, `country_config` derivation |
| `src/run.jl` | `run_simulation` / `run_simulation!` |

## Test

```bash
julia --project=core -e 'using Pkg; Pkg.test()'
```

## Status

- 135 native tests pass, including paper-1 closed-form checks, paper-2
equilibria/bounds/consumer–supplier balances, and paper-3 direction checks.
- Full feature parity with the papers: demurrage tax, VAT, tiered demurrage,
  granular SUMSY settlement, consumer–supplier transactions, equal distribution,
  one-time/constant injection and destruction, typed SuMSy by age, fixed money,
  and fixed/random loan-circuit modes.
- Phase 5a: the Belgium dataset and `country_config` derivation live here; the
  TypeScript country preset is generated from `belgium()`.
- The full minimal path runs under WasmTarget through `sim.wasm/wasm/`; paper 1
  and paper 2 are re-run end-to-end through the wasm ABI in
  `wasm/test/paper-parity-minimal.mjs`, and paper 3 scenarios in
  `wasm/test/paper3-minimal.mjs`.
- `Money` is Int64 scaled by 10^4. Paper-1 random-growth runs can exceed that
  range; the loan circuit saturates instead of wrapping, so the series stays
  finite (documented in the plan). The loan-rate mode reproduces the legacy
  per-loan debit rounding (`installment + interest` rounded once, with the
  running money balance rounded on each booking); this is what keeps the
  500-cycle stable and collapse trajectories aligned.

## Configuration style

Config values are grouped by concern and use named values, for example:

```julia
SimConfig(
    periods = 30_000,
    record_interval = 30,
    population = PopulationConfig(count = 100),
    wealth = WealthConfig(distribution = WealthDistribution.EQUAL,
                          equal_amount = money(0)),
    money = MoneyConfig(model = MoneyModel.SUMSY, interval = 30,
                        guaranteed_income = money(2_000),
                        demurrage = make_tiers(0.01)),
    transactions = TransactionConfig(enabled = false),
    tax = TaxConfig(kind = TaxKind.NONE))
```

WasmTarget 0.5.3 cannot lower `@enum` equality, so the named values are
`const Int32` constants in small modules. Call sites and the future schema are
unaffected.

## Not here yet

- The production module (blueprints, entities, needs, marginal actors) remains
  in the high-level `MoneySim` package; it is analysis tooling, not simulation
  state.
- The legacy `Country` enum registry stays in `MoneySim` for compatibility; the
  core uses typed `CountryData` values.
