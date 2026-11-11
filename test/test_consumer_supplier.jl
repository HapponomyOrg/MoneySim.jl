using Test
using Agents
using EconoSim
using MoneySim
using FixedPointDecimals
using DataFrames

@testset "Consumer Supplier - fixed demurrage" begin
    GI = 1000
    d = 0.01
    tu = 10
    L = 50
    consumers = 10

    sumsy = SuMSy(GI, 0, d)

    actor_data, model_data = run_consumer_supplier_simulation(sumsy,
                                                                sumsy_interval = tu,
                                                                sim_length = L,
                                                                num_suppliers = 1,
                                                                consumers_per_supplier = consumers,
                                                                fulfilled_demand = 5,
                                                                net_profit = 1,
                                                                suppliers_gi_eligible = false)

    # sim_length counts SuMSy periods; data is collected once per period, plus the initial state.
    @test nrow(actor_data) == (consumers + 1) * (L + 1)
    @test all(model_data[!, :num_actors] .== consumers + 1)

    # The supplier is not guaranteed-income eligible: everything it has, it earned by selling.
    supplier_rows = filter(row -> :supplier in row.types, actor_data)
    @test supplier_rows[!, :deposit][1] == 0
    @test supplier_rows[!, :deposit][end] > 0
end

@testset "Consumer Supplier Parameters" begin
    params = FixedConsumerSupplyParams(num_suppliers = 1,
                                        consumers_per_supplier = 10,
                                        demand = 5,
                                        price = 1)

    @test params.num_suppliers == 1
    @test params.consumers_per_supplier == 10
    @test params.demand == 5
    @test params.price == Currency(1)
end
