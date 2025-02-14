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

@testset "SuMsy - GDP yardsale" begin
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
    transaction_params = GDPYardSaleParams(gdp_period = 10,
                                            gdp_per_capita = 10000,
                                            wealth_transfer_range = 0.1:0.1:0.1,
                                            minimal_wealth_transfer = 0,
                                            remove_broke_actors = false)

    data = run_simulation(model,
                            sim_params = sim_params,
                            population_params = population_params,
                            monetary_params = monetary_params,
                            transaction_params = transaction_params,
                            data_handler = create_data_handler())
    
    id_groups = groupby(data[1], :id)

    for i in 1:size(id_groups[1])[1]
        @test id_groups[1][!, :deposit][i] + id_groups[2][!, :deposit][i] == 2 * telo(sumsy)
    end
end