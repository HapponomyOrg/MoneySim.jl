using EconoSim
using MoneySim
using Test
using DataFrames
using Agents

function post_data_processing!(actor_data, model_data)
    rename!(actor_data, 3 => :deposit)

    return actor_data, model_data
end

function create_data_handler(interval::Int = 1)
    return IntervalDataHandler(interval = interval,
                                actor_data_collectors = [deposit_collector, :gi, :dem],
                                model_data_collectors = [],
                                post_processing! = post_data_processing!)
end

@testset "SuMSy - standard SuMSy params - homogenic actors" begin
    sumsy = SuMSy(2000, 0, 0.1)
    model = create_sumsy_model(sumsy_interval = 1,
                                model_behaviors = process_model_sumsy!)
    sim_params = SimParams(5)
    population_params = FixedPopulationParams(population = 2,
                                                create_actor! = m -> create_sumsy_actor!(m,
                                                                                        sumsy = sumsy,
                                                                                        sumsy_interval = 1,
                                                                                        allow_negative_sumsy = true,
                                                                                        allow_negative_demurrage = false))
    monetary_params = StandardSuMSyParams(sumsy_interval = 1,
                                            transactional = false,
                                            configure_sumsy_actors! = m -> mixed_actors!(m, nagents(m)),
                                            distribute_wealth! = m -> distribute_equal!(m, telo(sumsy)))

    data = run_simulation(model,
                            sim_params = sim_params,
                            population_params = population_params,
                            monetary_params = monetary_params,
                            transaction_params = BareBonesParams(),
                            data_handler = create_data_handler())
    
    for i in 1:size(data[1])[1]
        @test data[1][!, :gi][i] == data[1][!, :dem][i]
        @test data[1][!, :deposit][i] == telo(sumsy)
    end
end

@testset "SuMSy - standard SuMSy params - typed actors - distribute equal" begin
    sumsy_groups = Dict{Symbol, Tuple{Real, Real}}(:group_1 => (1000, 0),
                                                    :group_2 => (2000, 0))

    sumsy = SuMSy(2000, 0, 0.1)
    model = create_sumsy_model(sumsy_interval = 1,
                                model_behaviors = process_model_sumsy!)
    sim_params = SimParams(5)
    population_params = FixedPopulationParams(population = 2,
                                                create_actor! = m -> create_sumsy_actor!(m,
                                                                                        sumsy = sumsy,
                                                                                        sumsy_interval = 1,
                                                                                        allow_negative_sumsy = true,
                                                                                        allow_negative_demurrage = false))
    monetary_params = StandardSuMSyParams(sumsy_interval = 1,
                                            transactional = false,
                                            configure_sumsy_actors! = m -> type_based_sumsy_actors!(m, sumsy_groups, 0.1),
                                            distribute_wealth! = m -> distribute_equal!(m, telo(sumsy)))

    data = run_simulation(model,
                            sim_params = sim_params,
                            population_params = population_params,
                            monetary_params = monetary_params,
                            transaction_params = BareBonesParams(),
                            data_handler = create_data_handler())
    
    for i in 1:size(data[1])[1]
        @test data[1][!, :gi][i] == data[1][!, :dem][i]
        @test data[1][!, :deposit][i] == telo(sumsy)
    end
end