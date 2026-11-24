# Common-RNG plain yard-sale loop: legacy MoneySim driven by the core xorshift
# stream, compared step by step with `MoneySimCore.transactions_step!`.
#
# Run with:
#   julia --project=. test/parity/common_rng_yardsale.jl

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

"""Legacy `AbstractRNG` adapter that draws from the core Rng."""
mutable struct CoreRng <: AbstractRNG
    rng::EC.Rng
end

Random.rand(rng::CoreRng, ::Type{Float64}) = EC.rand_unit(rng.rng)
Random.rand(rng::CoreRng, r::UnitRange{Int}) =
    first(r) + EC.rand_index(rng.rng, length(r)) - 1
Random.rand(rng::CoreRng, r::AbstractRange) = (EC.rand_unit(rng.rng); first(r))

const INITIAL_WEALTH = [100, 200, 300, 400]
const TRANSACTIONS_PER_STEP = 5
const STEPS = 8

@testset "common RNG yard-sale parity" begin
    n = length(INITIAL_WEALTH)

    model = create_econo_model(MonetaryActor{EconoSim.Currency,
                                             Balance{EconoSim.Currency}})
    for _ in 1:n
        add_agent!(MonetaryActor{EconoSim.Currency, Balance{EconoSim.Currency}},
                   model;
                   model = model, balance = Balance(), income = 0, expenses = 0,
                   types = Set{Symbol}(), behaviors = Function[])
    end
    for (i, value) in enumerate(INITIAL_WEALTH)
        book_asset!(get_balance(model[i]), SUMSY_DEP, value)
    end

    params = StandardYardSaleParams(
        transaction_range = TRANSACTIONS_PER_STEP:TRANSACTIONS_PER_STEP,
        wealth_transfer_range = 0.2:0.2:0.2,
        minimal_wealth_transfer = 0,
        determine_direction = MoneySim.coinflip,
        wealth_accumulation_advantage = 0.0,
        average_wealth = m -> 250.0)
    MoneySim.initialize_transaction_model!(model, params)

    abmproperties(model)[:rng] = CoreRng(EC.Rng(42))

    state = MC.SimState(n)
    for i in 1:n
        state.wealth[i] = EC.money(INITIAL_WEALTH[i])
    end
    cfg = MC.TransactionConfig(enabled = true,
                               transactions_per_step = TRANSACTIONS_PER_STEP,
                               transfer_rate = 0.2,
                               wealth_advantage = 0.0)
    money = MC.MoneyConfig(model = MC.MoneyModel.FIXED, interval = 1)
    core_rng = EC.Rng(42)

    for step in 1:STEPS
        MoneySim.yard_sale!(model, MoneySim.coinflip, nothing)
        MC.transactions_step!(state, cfg, money, core_rng, step)

        for i in 1:n
            legacy = Float64(asset_value(get_balance(model[i]), SUMSY_DEP))
            @test EC.currency(state.wealth[i]) == legacy
        end
        @test EC.currency(MC.total_wealth(state)) ==
              Float64(sum(asset_value(get_balance(model[i]), SUMSY_DEP)
                          for i in 1:n))
    end
end
