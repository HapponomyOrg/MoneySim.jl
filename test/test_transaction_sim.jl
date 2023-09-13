using Test
using DataFrames
using EconoSim

@testset "Fixed wealth sim - standard yard sale" begin
    sim_params = SimParams(true, 100, 10, 1:10)
    fixed_wealth_params = FixedWealthParams(1000, 1000, true)
    transaction_params = YardSaleParams(0.2:0.001:0.2, 0)

    run_fixed_wealth_simulation(sim_params, fixed_wealth_params, transaction_params)
end

@testset "SuMSy sim - standard yard sale - non-transactional" begin
    sim_params = SimParams(true, 100, 10, 1:10)
    initial_wealth = telo(2000, 25000, 0.01)
    sumsy_params = SuMSyParams(2000, 25000, 0.01, false, 990, initial_wealth, 10, initial_wealth, true)
    transaction_params = YardSaleParams(0.2:0.001:0.2, 0)

    run_sumsy_simulation(sim_params, sumsy_params, transaction_params)
end

@testset "SuMSy sim - standard yard sale - transactional" begin
    sim_params = SimParams(true, 100, 10, 1:10)
    initial_wealth = telo(2000, 25000, 0.01)
    sumsy_params = SuMSyParams(2000, 25000, 0.01, true, 990, initial_wealth, 10, initial_wealth, true)
    transaction_params = YardSaleParams(0.2:0.001:0.2, 0)

    run_sumsy_simulation(sim_params, sumsy_params, transaction_params)
end