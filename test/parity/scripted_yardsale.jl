# One stochastic transaction through legacy MoneySim and MoneySimCore with a
# shared logical draw order.
#
# Run with:
#   julia --project=. test/parity/scripted_yardsale.jl

using Test
using Random
using Agents
using EconoSim
using MoneySim
import EconoSimCore
import MoneySimCore

const EC = EconoSimCore
const MC = MoneySimCore

set_currency_precision!(4)

"""A legacy-RNG adapter that replays logical draws, not raw bits."""
mutable struct ScriptedLegacyRng <: AbstractRNG
    indices::Vector{Int}
    units::Vector{Float64}
end

Random.rand(rng::ScriptedLegacyRng, r::UnitRange{Int}) = popfirst!(rng.indices)
Random.rand(rng::ScriptedLegacyRng) = popfirst!(rng.units)
Random.rand(rng::ScriptedLegacyRng, r::AbstractRange) = first(r)

function _legacy_direction(rng)
    return (target1, av1, target2, av2, waa, avg_wealth) -> begin
        raw_bias = waa * (av1 - av2) / avg_wealth
        bias = clamp(raw_bias, -1.0, 1.0)
        probability_first = (1.0 + bias) / 2.0
        return rand(rng) < probability_first ? (target2, target1) : (target1, target2)
    end
end

@testset "scripted yard sale parity" begin
    # Legacy: two actors, 100 and 200; pick 1 then 2, transfer 20 to actor 1.
    model = create_econo_model(MonetaryActor{EconoSim.Currency,
                                             Balance{EconoSim.Currency}})
    for _ in 1:2
        add_agent!(MonetaryActor{EconoSim.Currency, Balance{EconoSim.Currency}},
                   model;
                   model = model, balance = Balance(), income = 0, expenses = 0,
                   types = Set{Symbol}(), behaviors = Function[])
    end
    first_actor = model[1]
    second_actor = model[2]

    book_asset!(get_balance(first_actor), SUMSY_DEP, 100)
    book_asset!(get_balance(second_actor), SUMSY_DEP, 200)

    props = abmproperties(model)
    props[:wealth_transfer_range] = 0.2:0.2:0.2
    props[:waa] = 0.0
    props[:minimal_wealth_transfer] = 0

    legacy_rng = ScriptedLegacyRng([1, 2], [0.0])
    source, destination, amount = MoneySim.atomic_yard_sale!(
        model, _legacy_direction(legacy_rng), [first_actor.id, second_actor.id],
        150.0; rng = legacy_rng)

    @test source.id == second_actor.id
    @test destination.id == first_actor.id
    @test Float64(amount) == 20.0
    @test Float64(asset_value(get_balance(first_actor), SUMSY_DEP)) == 120.0
    @test Float64(asset_value(get_balance(second_actor), SUMSY_DEP)) == 180.0

    # Core: same logical draws, encoded as raw xorshift values.
    state = MC.SimState(2)
    state.wealth[1] = EC.money(100)
    state.wealth[2] = EC.money(200)
    core_rng = EC.Rng([0, 1, 0])
    moved = MC.yardsale_transfer!(
        state,
        MC.TransactionConfig(enabled = true, transactions_per_step = 1,
                             transfer_rate = 0.2, wealth_advantage = 0.0),
        MC.MoneyConfig(model = MC.MoneyModel.FIXED, interval = 1),
        core_rng, 150.0, 1)

    @test EC.currency(moved) == 20.0
    @test EC.currency(state.wealth[1]) == 120.0
    @test EC.currency(state.wealth[2]) == 180.0
    @test EC.currency(state.step_income[1]) == 20.0
    @test EC.currency(state.step_expenses[2]) == 20.0
end
