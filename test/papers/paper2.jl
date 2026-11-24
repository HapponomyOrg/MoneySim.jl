# Paper 2 — alternative general-purpose money supply (SUMSY).
#
# Scenario parameters and expected bounds come from `scenarios.jl`; the values
# are taken from jupyter/paper 2/Alternative.ipynb and alternative_sim.jl.
#
# `scenarios.jl` must be included before this file.

using Test
using MoneySim
using EconoSim: telo, SuMSy

const TIERED_DEMURRAGE = [
    (0.0, 0.01),
    (50_000.0, 0.02),
    (500_000.0, 0.05),
    (1_000_000.0, 0.10),
    (10_000_000.0, 0.50),
    (50_000_000.0, 0.95),
]

# The 750-period equilibria dominate the runtime. PR CI runs the short
# scenarios; `PAPER_TESTS=full` runs all of them.
const PAPER2_FAST_SCENARIOS = Set([:a1, :a2, :b1, :b2])
const PAPER_TEST_MODE = get(ENV, "PAPER_TESTS", "fast")

function _tiers(params)
    params.demurrage_tiers === nothing ? params.demurrage : collect(params.demurrage_tiers)
end

function _sumsy(params)
    SuMSy(params.gi, params.demurrage_free, _tiers(params))
end

function _adaptation(name)
    name === :none && return nothing
    name === :one_time_injection && return one_time_money_injection!
    name === :constant_injection && return constant_money_injection!
    name === :one_time_destruction && return one_time_money_destruction!
    name === :constant_destruction && return constant_money_destruction!
    name === :equal_distribution && return equal_money_distribution!
    error("unknown adaptation: $name")
end

function _run_sumsy(params)
    data = run_sumsy_simulation(_sumsy(params);
        sumsy_interval = params.interval,
        granularity = :transactional in keys(params) && params.transactional ?
            1 : params.interval,
        eligible_actors = params.eligible,
        non_eligible_actors = params.noneligible,
        num_transactions = params.transactions,
        sim_length = params.periods,
        distributed = params.distributed,
        data_handler = money_stock_data_handler(params.interval),
        model_adaptation = _adaptation(params.adaptation))[1]

    return analyse_aggregate(data)
end

function _bound(bound, params)
    bound isa Symbol || return Float64(bound)

    tiers = _tiers(params)
    if bound === :telo_gi
        return Float64(telo(params.gi, tiers) * params.eligible)
    elseif bound === :telo_gi_df
        return Float64(telo(params.gi, tiers, params.demurrage_free) * params.eligible)
    elseif bound === :telo_total
        return Float64(telo(params.gi * params.eligible, tiers))
    elseif bound === :telo_equal
        gi_eq = params.gi * params.eligible / (params.eligible + params.noneligible)
        return Float64(telo(gi_eq, tiers) * (params.eligible + params.noneligible))
    end

    error("unknown bound: $bound")
end

function _run_consumer_supplier(params, case)
    data = run_consumer_supplier_simulation(_sumsy(params);
        sumsy_interval = params.interval,
        sim_length = params.periods,
        num_suppliers = 1,
        consumers_per_supplier = case.consumers,
        fulfilled_demand = case.fulfilled_demand,
        net_profit = case.net_profit,
        suppliers_gi_eligible = false)[1]

    typed = analyse_type_data(data)
    return Float64(last(typed.supplier))
end

@testset "Paper 2 — SUMSY equilibria" begin
    @testset "telo, flat demurrage" begin
        @test Float64(telo(2000.0, 0.01)) == 200_000.0
        @test Float64(telo(2000.0, 0.01, 25_000.0)) == 225_000.0
    end

    @testset "telo, tiered demurrage" begin
        # telo(200_000, tiers) is the paper's lower bound for e2/e3/e4/e5.
        @test Float64(telo(200_000.0, TIERED_DEMURRAGE)) ≈ 2_655_000.0 rtol = 1e-6
        # GI_eq for 100 eligible + 25 non-eligible actors.
        gi_eq = 2000.0 * 100 / 125
        @test Float64(telo(gi_eq, TIERED_DEMURRAGE) * 125) ≈ 13_125_000.0 rtol = 1e-6
    end

    @testset "scenario manifest" begin
        names = Set(s.name for s in PAPER2_SCENARIOS)
        @test names == Set([:a1, :a2, :b1, :b2, :s1, :s2, :s3, :s4,
                            :e1, :e2, :e3, :e4, :e5, :d1])
        @test length(PAPER2_CONSUMER_SUPPLIER) == 2
    end

    @testset "money-stock scenarios" begin
        for scenario in PAPER2_SCENARIOS
            if PAPER_TEST_MODE == "fast" && !(scenario.name in PAPER2_FAST_SCENARIOS)
                @test_skip "$(scenario.name) — slow; run with PAPER_TESTS=full"
                continue
            end

            @testset "$(scenario.name)" begin
                aggregate = _run_sumsy(scenario.params)
                final_money = Float64(last(aggregate.money_stock))
                expected = scenario.expected

                if :money_stock_target in keys(expected)
                    @test final_money ≈ expected.money_stock_target rtol = 0.01
                end
                if :money_stock_min in keys(expected)
                    @test final_money >= _bound(expected.money_stock_min, scenario.params) * 0.99
                end
                if :money_stock_max in keys(expected)
                    @test final_money <= _bound(expected.money_stock_max, scenario.params) * 1.01
                end
                if :finite in keys(expected) && expected.finite
                    @test isfinite(final_money)
                end
                if :money_stock_positive in keys(expected) && expected.money_stock_positive
                    @test final_money > 0
                end
            end
        end
    end

    @testset "consumer–supplier scenarios" begin
        for scenario in PAPER2_CONSUMER_SUPPLIER
            @testset "$(scenario.name)" begin
                for case in scenario.cases
                    balance = _run_consumer_supplier(scenario.params, case)
                    @test balance ≈ case.expected_balance rtol = 0.001
                end
            end
        end
    end
end
