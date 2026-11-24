using Test
using DataFrames
using EconoSim
using MoneySim

@testset "Gini calculation" begin
    df = DataFrame(equal = Currency[], unequal = Currency[])

    for i in 1:999
        push!(df, [0.001 0])
    end
    push!(df, [0.001 1])

    @test MoneySim.calculate_gini(1, eachrow(df), :equal) == 0
    # One actor holds everything: the Gini coefficient of n actors is 1 - 1/n.
    # (The former expectation, round(1 - 0.001, digits = 2) == 1.0, did not match the formula's 4-digit rounding.)
    @test MoneySim.calculate_gini(1, eachrow(df), :unequal) == 1 - 1 / 1000
end

# The money stock and wealth analysis testsets were rewritten on 2026-11-11: analyse_money_stock and
# analyse_wealth are no longer defined; analyse_aggregate and analyse_data do the same job.

@testset "Money stock analysis" begin
    num_actors = 100
    actor_data, _ = run_fixed_wealth_simulation(num_actors = num_actors,
                                                num_transactions = 10,
                                                initial_wealth = 1000,
                                                sim_length = 10,
                                                period = 1)
    analysis = analyse_aggregate(actor_data)

    @test analysis[!, :cycle] == 0:10
    @test all(analysis[!, :money_stock] .== num_actors * 1000)
end

@testset "Wealth analysis" begin
    num_actors = 100
    data = run_fixed_wealth_simulation(num_actors = num_actors,
                                        num_transactions = 10,
                                        initial_wealth = 1000,
                                        sim_length = 10,
                                        period = 1)
    analysis = analyse_data(data, wealth = :deposit, income = :equity)

    # At the start everybody has the same wealth.
    @test analysis[WEALTH_GINI][1, :wealth_gini] == 0
    @test analysis[W_NOMINAL][1, :TOP_10] == 10 * 1000
    @test analysis[W_PERCENTAGE][1, :BOTTOM_50] == 50
    @test nrow(analysis[W_NOMINAL]) == 11
end
