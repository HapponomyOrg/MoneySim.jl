using Test
using Agents
using EconoSim
using MoneySim
using FixedPointDecimals

@testset "Consumer Supplier - fixed demurrage" begin
    GI = 1000
    d = 0.01
    tu = 10
    L = 50

    sumsy = SuMSy(GI, 0, d)

    data = run_consumer_supplier_simulation(sumsy,
                                            sumsy_interval = tu,
                                            sim_length = L,
                                            num_suppliers = 1,
                                            consumers_per_supplier = 10,
                                            fulfilled_demand = 5,
                                            net_profit = 1,
                                            suppliers_gi_eligible = false)
end

@testset "Consumer Supplier Parameters" begin
    FixedConsumerSupplyParams(1, 10, 5, 1)
end