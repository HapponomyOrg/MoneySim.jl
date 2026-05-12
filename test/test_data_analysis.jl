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
    @test MoneySim.calculate_gini(1, eachrow(df), :unequal) == round(1 - 0.001, digits = 2)
end

@testset "Money stock analysis" begin    
    sim_params = SimParams(10)
    fixed_wealth_params = FixedWealthParams(distribute_equal!)
    transaction_params = StandardYardSaleParams(transaction_range = 1:1,
                                                wealth_transfer_range = 0.2:0.2,
                                                minimal_wealth_transfer = 0,
                                                remove_broke_actors = false,
                                                average_wealth = 1000)

    data = run_fixed_wealth_simulation(sim_params, fixed_wealth_params, transaction_params)
    analyse_money_stock(data)
end

@testset "Wealth analysis" begin    
    sim_params = SimParams(10)
    fixed_wealth_params = FixedWealthParams(distribute_equal!)
    transaction_params = StandardYardSaleParams(transaction_range = 1:1,
                                                wealth_transfer_range = 0.2:0.2,
                                                minimal_wealth_transfer = 0,
                                                remove_broke_actors = false,
                                                average_wealth = 1000)

    data = run_fixed_wealth_simulation(sim_params, fixed_wealth_params, transaction_params)
    analyse_wealth(data, fixed_wealth_params.num_actors)
end