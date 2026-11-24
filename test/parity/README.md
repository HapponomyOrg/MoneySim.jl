# Scripted stochastic parity

Runs one stochastic yard-sale transaction through legacy `MoneySim` and
`MoneySimCore` under the same logical random draws.

```bash
julia --project=. test/parity/scripted_yardsale.jl
julia --project=. test/parity/scripted_gdp.jl
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
the same 100 target with the same final balances (3/3 checks). The script follows
legacy's actual candidate-list order, because the legacy ABM is a `Dict`.

## Remaining for full paper 3

The transaction and GDP loops are now aligned under a scripted RNG. Full
paper-3 bit parity still needs the remaining stochastic paths aligned: random
tax-redistribution remainders and any model adaptations that draw from the
global RNG.
