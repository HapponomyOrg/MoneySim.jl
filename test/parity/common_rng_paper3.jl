# Full paper-3 a1 with a common xorshift stream.
#
# Run with:
#   julia --project=. test/parity/common_rng_paper3.jl

using Test
using Random
using EconoSim
using MoneySim
import EconoSimCore
import MoneySimCore

const EC = EconoSimCore

set_currency_precision!(4)

mutable struct CoreRng <: AbstractRNG
    rng::EC.Rng
end

Random.rand(rng::CoreRng, ::Type{Float64}) = EC.rand_unit(rng.rng)
Random.rand(rng::CoreRng, r::UnitRange{Int}) = EC.rand_index(rng.rng, length(r))
Random.rand(rng::CoreRng, r::AbstractRange) = (EC.rand_unit(rng.rng); first(r))

const PAPER_DIR = joinpath(pwd(), "test", "papers")
include(joinpath(PAPER_DIR, "scenarios.jl"))
include(joinpath(PAPER_DIR, "adapter.jl"))

@testset "common RNG paper 3 a1" begin
    scenario = only(filter(x -> x.name === :a1, PAPER3_SCENARIOS))
    legacy = _paper3_legacy(scenario, 1_000, 10;
                            rng = CoreRng(EC.Rng(42)))
    core = run_paper3(scenario; backend = :core, actors = 1_000,
                      years = 10, seed = 42)

    @test isapprox(core.gini_wealth, legacy.gini_wealth; atol = 1e-3)
    @test isapprox(core.money_stock, legacy.money_stock; rtol = 2e-3)
    @test isapprox(core.public_debt, legacy.public_debt; rtol = 1e-6)
    @test isapprox(core.top10_share, legacy.top10_share; atol = 0.5)
    @test isapprox(core.bottom50_share, legacy.bottom50_share; atol = 0.5)
end
