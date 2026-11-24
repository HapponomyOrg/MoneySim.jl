# Common-RNG paper-2 suite: every SUMSy scenario under one shared stream.
#
# Run with:
#   julia --project=. test/parity/common_rng_paper2.jl

using Test
using Random
using Printf
using Agents
using EconoSim
using MoneySim
import EconoSimCore
import MoneySimCore

const EC = EconoSimCore
const MC = MoneySimCore

set_currency_precision!(4)

"""Legacy `AbstractRNG` adapter that draws from the core Rng."""
mutable struct CoreRng <: AbstractRNG
    rng::EC.Rng
end

Random.rand(rng::CoreRng, ::Type{Float64}) = EC.rand_unit(rng.rng)
Random.rand(rng::CoreRng, r::UnitRange{Int}) =
    first(r) + EC.rand_index(rng.rng, length(r)) - 1
Random.rand(rng::CoreRng, r::AbstractRange) = (EC.rand_unit(rng.rng); first(r))

const PAPER_DIR = joinpath(pwd(), "test", "papers")
include(joinpath(PAPER_DIR, "scenarios.jl"))
include(joinpath(PAPER_DIR, "adapter.jl"))

# The 750-period equilibria dominate the runtime. The default set covers the
# short scenarios plus the two tiered-demurrage cases that used to diverge;
# `PAPER_TESTS=full` runs every paper-2 scenario.
const FAST_SCENARIOS = Set([:a1, :a2, :b1, :b2, :e2, :e5])
const PARITY_MODE = get(ENV, "PAPER_TESTS", "fast")

@testset "common RNG paper 2" begin
    for scenario in PAPER2_SCENARIOS
        if PARITY_MODE != "full" && !(scenario.name in FAST_SCENARIOS)
            @test_skip "$(scenario.name) — slow; run with PAPER_TESTS=full"
            continue
        end

        legacy = _paper2_legacy_sumsy(scenario.params; rng = CoreRng(EC.Rng(42)))
        core = _paper2_core_sumsy(scenario.params)
        @printf("  %-3s money %.6e | max %.6e | min %.6e\n",
                String(scenario.name), core.money_stock,
                core.max_money_stock, core.min_money_stock)

        @testset "$(scenario.name)" begin
            @test core.money_stock == legacy.money_stock
            @test core.max_money_stock == legacy.max_money_stock
            @test core.min_money_stock == legacy.min_money_stock
        end
    end
end
