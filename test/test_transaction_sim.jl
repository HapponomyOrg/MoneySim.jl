using Test
using DataFrames
using EconoSim
using MoneySim

# Rewritten on 2026-11-11 to the current runners. The former testsets called SimParams with four arguments,
# the abstract YardSaleParams as a constructor and a nine-argument SuMSyParams, none of which exist any more.

@testset "Fixed wealth sim - standard yard sale" begin
    num_actors = 100
    initial_wealth = 1000

    actor_data, model_data = run_fixed_wealth_simulation(num_actors = num_actors,
                                                        num_transactions = 50,
                                                        initial_wealth = initial_wealth,
                                                        sim_length = 10,
                                                        period = 10)

    @test sort(unique(actor_data[!, :time])) == 0:10:100
    @test all(model_data[!, :num_actors] .== num_actors)

    # Trades only move money: the money stock stays the same.
    for group in groupby(actor_data, :time)
        @test sum(group[!, :deposit]) == num_actors * initial_wealth
    end
end

@testset "SuMSy sim - standard yard sale - default granularity" begin
    sumsy = SuMSy(2000, 0, 0.01)
    num_actors = 100

    actor_data, model_data = run_sumsy_simulation(sumsy,
                                                    sumsy_interval = 10,
                                                    eligible_actors = num_actors,
                                                    num_transactions = 50,
                                                    sim_length = 10)
    money_stock = analyse_aggregate(actor_data)[!, :money_stock]

    # With a flat demurrage and no demurrage-free buffer, guaranteed income and demurrage balance at telo.
    @test money_stock[1] == telo(sumsy) * num_actors
    @test all(m -> isapprox(m, telo(sumsy) * num_actors, rtol = 1e-6), money_stock)
end

@testset "SuMSy sim - standard yard sale - granularity 1" begin
    sumsy = SuMSy(2000, 0, 0.01)
    num_actors = 100

    actor_data, model_data = run_sumsy_simulation(sumsy,
                                                    sumsy_interval = 10,
                                                    granularity = 1,
                                                    eligible_actors = num_actors,
                                                    num_transactions = 50,
                                                    sim_length = 10)
    money_stock = analyse_aggregate(actor_data)[!, :money_stock]

    @test money_stock[1] == telo(sumsy) * num_actors
    @test all(m -> isapprox(m, telo(sumsy) * num_actors, rtol = 1e-6), money_stock)
end
