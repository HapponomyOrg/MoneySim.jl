# Scripted GDP yard-sale loop: legacy MoneySim vs MoneySimCore.
#
# Run with:
#   julia --project=. test/parity/scripted_gdp.jl

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

mutable struct ScriptedLegacyRng <: AbstractRNG
    indices::Vector{Int}
    units::Vector{Float64}
end

Random.rand(rng::ScriptedLegacyRng, r::UnitRange{Int}) = popfirst!(rng.indices)
Random.rand(rng::ScriptedLegacyRng) = popfirst!(rng.units)
Random.rand(rng::ScriptedLegacyRng, ::Type{Float64}) = popfirst!(rng.units)
Random.rand(rng::ScriptedLegacyRng, r::AbstractRange) = first(r)

@testset "scripted GDP loop parity" begin
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

    params = GDPYardSaleParams(
        gdp_period = 1, gdp_per_capita = 50, gdp_growth = (m, p) -> 0.0,
        wealth_transfer_range = 0.2:0.2:0.2,
        minimal_wealth_transfer = 0,
        determine_direction = MoneySim.coinflip,
        average_wealth = m -> 150.0)
    MoneySim.initialize_transaction_model!(model, params)

    # Follow legacy's actual candidate order (its ABM is a Dict).
    ids = MoneySim.get_non_broke_actor_ids(model)
    first_index = findfirst(==(first_actor.id), ids)
    second_index = findfirst(==(second_actor.id), ids)
    indices = repeat([first_index, second_index], 1000)
    units = zeros(1000)
    legacy_rng = ScriptedLegacyRng(indices, units)
    abmproperties(model)[:rng] = legacy_rng
    MoneySim.gdp_yard_sale!(model, MoneySim.coinflip, nothing)

    legacy_first = Float64(asset_value(get_balance(first_actor), SUMSY_DEP))
    legacy_second = Float64(asset_value(get_balance(second_actor), SUMSY_DEP))

    function raw_index(index)
        return UInt64(index - 1)
    end
    function raw_unit(unit)
        return UInt64(floor(unit * 9_007_199_254_740_992.0)) << 11
    end
    script = UInt64[]
    for _ in 1:1000
        push!(script, raw_index(1), raw_index(2), 0, raw_unit(0.0))
    end

    state = MC.SimState(2)
    state.wealth[1] = EC.money(100)
    state.wealth[2] = EC.money(200)
    state.gdp_target = EC.money(100)
    core_rng = EC.Rng(script)
    MC.gdp_transactions_step!(
        state,
        MC.TransactionConfig(enabled = true, transfer_rate = 0.2,
                             wealth_advantage = 0.0),
        MC.GdpConfig(enabled = true, per_capita = EC.money(50),
                     growth_ppm = 0, interval = 1),
        MC.MoneyConfig(model = MC.MoneyModel.FIXED, interval = 1),
        core_rng, 1)

    @test EC.currency(state.wealth[1]) == legacy_first
    @test EC.currency(state.wealth[2]) == legacy_second
    @test EC.currency(state.wealth[1] + state.wealth[2]) == 300.0
end
