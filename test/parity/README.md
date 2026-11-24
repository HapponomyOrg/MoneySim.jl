# Scripted stochastic parity

Runs one stochastic yard-sale transaction through legacy `MoneySim` and
`MoneySimCore` under the same logical random draws.

```bash
julia --project=. test/parity/scripted_yardsale.jl
```

The legacy model now accepts an explicit `rng` for `atomic_yard_sale!` and
`yard_sale_transfer`; the default remains `Random.default_rng()`, so normal
seeded runs are unchanged. The test uses:

- a legacy `ScriptedLegacyRng` that replays index/direction draws;
- the core `Rng([0, 1, 0])` replay stream;
- two actors with balances 100 and 200.

Both implementations must select actor 1 then 2, transfer 20 units to actor 1,
and end at 120 / 180. The test currently passes 10/10 checks.

## Not covered yet

The full GDP/paper-3 loop still has different draw order: legacy samples from a
prebuilt non-broke list, core uses rejection sampling. A full model trace
comparison needs those loops aligned.
