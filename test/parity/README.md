# Scripted stochastic parity

Runs one stochastic yard-sale transaction through legacy `MoneySim` and
`MoneySimCore` under the same logical random draws.

```bash
julia --project=. test/parity/scripted_yardsale.jl
julia --project=. test/parity/scripted_gdp.jl
julia --project=. test/parity/common_rng_gdp.jl
julia --project=. test/parity/common_rng_yardsale.jl
julia --project=. test/parity/common_rng_paper3.jl
```

The legacy model now accepts an explicit `rng` for `atomic_yard_sale!`,
`yard_sale_transfer`, and `SimParams` (`rng = ...`). `gdp_yard_sale!` and
`yard_sale!` read it from the model, so a whole run can be driven by a supplied
generator. The default remains `Random.default_rng()`, so normal seeded runs are
unchanged. The test uses:

- a legacy `ScriptedLegacyRng` that replays index/direction draws;
- the core `Rng([0, 1, 0])` replay stream;
- two actors with balances 100 and 200.

Both implementations must select actor 1 then 2, transfer 20 units to actor 1,
and end at 120 / 180. The test passes 10/10 checks.

`scripted_gdp.jl` runs a complete GDP yard-sale loop: legacy and core must reach
the same 100 target with the same final balances (3/3 checks).

`common_rng_gdp.jl` drives legacy with a `CoreRng` adapter around the actual
xorshift64 core generator. The GDP loop matches exactly (3/3 checks), proving
common-random-number parity for that path.

`common_rng_yardsale.jl` does the same for the plain (non-GDP) yard-sale loop
over eight steps with four actors. The core builds the non-broke candidate list
once per step, draws both indices from it with legacy's duplicate adjustment,
consumes the transfer-rate draw, and drops broke actors after each transfer.
All 40 checks (wealth vector and money stock, every step) match exactly. The
step also consumes the draw legacy makes for its single-valued transaction
range, so both streams stay in step.

`common_rng_paper3.jl` runs full paper-3 `a1` under the same shared stream. It
checks Gini within 5e-4, money within 1e-6, debt within 1e-6, and shares within
0.5 pp (5/5). It then runs all 17 paper-3 scenarios under the same stream, with
Gini within 0.03, money/debt within 1%, and tax within 1.5% (66/66). Across all
scenarios the largest common-RNG deltas are Gini 0.0235 (`c5`), money 0.506%
(`c1`), and tax 1.345% (`a9`).

## Remaining for full paper 3

The transaction loop, GDP loop, tax-redistribution remainder, and rounded GDP
target growth are aligned. The country demurrage calibration is rounded to four
decimals like legacy, and the initial wealth vectors match exactly. Full
paper-3 `a1` now matches money to 0.0195 and Gini to 3.1e-4 under the shared
xorshift stream; the remaining gap is transaction-amount rounding.

## Draw-order coverage

Every random draw in the legacy paths that the papers and country simulations
use now has a counterpart in the core:

| Legacy draw | Core draw |
|---|---|
| `rand(rng, transaction_range)` | one `rand_index(rng, 1)` per step |
| `rand(rng, 1:num_non_broke)` ×2 + duplicate adjustment | `_atomic_yardsale!` |
| `rand(rng, wealth_transfer_range)` | `rand_unit` (rate is fixed in core) |
| `rand(rng)` in `coinflip` | `rand_unit` in `_yardsale_at!` |
| `rand(rng, 1:length(tax_recipients))` | `_add_remainder!` |
| GDP target growth and period bookkeeping | `gdp_transactions_step!` |

Out of scope because the core has no corresponding stochastic step:
`wealth_weighted_direction` (unused; country sims use `coinflip`),
`run_consumer_supplier_simulation`'s sampled price/demand helpers (the core
consumer–supplier step is deterministic), and `adjust_population!` in
`model_adaptations.jl` (unused; the papers configure a fixed population).
Demographic aging in `population_step!` consumes its own draws and is not part
of the common-stream comparison.
