# Scripted stochastic parity

Runs one stochastic yard-sale transaction through legacy `MoneySim` and
`MoneySimCore` under the same logical random draws.

```bash
julia --project=. test/parity/scripted_yardsale.jl
julia --project=. test/parity/scripted_gdp.jl
julia --project=. test/parity/common_rng_gdp.jl
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

`common_rng_paper3.jl` runs full paper-3 `a1` under the same shared stream. It
checks Gini within 1e-3, money within 0.2%, debt within 1e-6, and shares within
0.5 pp (5/5).

## Remaining for full paper 3

The transaction loop, GDP loop, tax-redistribution remainder, and rounded GDP
target growth are aligned. With a shared xorshift stream, full paper-3 `a1`
matches Gini to ~7×10⁻⁵ (0.455700 vs 0.455628); the remaining 0.11% money-level
gap is SUMSY/initial-distribution rounding, not draw order.
