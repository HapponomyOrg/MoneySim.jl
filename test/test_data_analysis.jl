using Test
using DataFrames
using EconoSim

@testset "Money stock analysis" begin
    
    sim_params = SimParams(true, 100, 10, 1:10)
    fixed_wealth_params = FixedWealthParams(1000, 1000, true)
    transaction_params = YardSaleParams(0.2:0.001:0.2, 0)

    data = run_fixed_wealth_simulation(sim_params, fixed_wealth_params, transaction_params)
    analyse_money_stock(data)
end

@testset "Wealth analysis" begin
    
    sim_params = SimParams(true, 100, 10, 1:10)
    fixed_wealth_params = FixedWealthParams(1000, 1000, true)
    transaction_params = YardSaleParams(0.2:0.001:0.2, 0)

    data = run_fixed_wealth_simulation(sim_params, fixed_wealth_params, transaction_params)
    analyse_wealth(data, fixed_wealth_params.num_actors)
end