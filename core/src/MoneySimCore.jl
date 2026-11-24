"""
    MoneySimCore

Dependency-free simulation core for MoneySim: population, SUMSY money creation
and demurrage, yard-sale transactions, taxes, and aggregate metrics.

This package contains no Agents.jl, DataFrames, plotting, or wasm tooling. It
depends only on `EconoSimCore`.

Phase 2 implements the minimal path: SUMSY + yard sale + wealth tax + metrics.
Income tax, demographics, government, GDP, and adaptations follow in Phase 4.
"""
module MoneySimCore

using EconoSimCore

include("types.jl")
include("state.jl")
include("metrics.jl")
include("transactions.jl")
include("taxes.jl")
include("adaptations.jl")
include("money_models.jl")
include("population.jl")
include("run.jl")
include("countries.jl")

end
