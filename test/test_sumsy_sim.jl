using EconoSim
using MoneySim
using Test
using Agents
using DataFrames

# Rewritten on 2026-11-11. The former file built SuMSy with a removed constructor (interval and transactional
# arguments) and had no assertions. Transactional SuMSy is now settlement granularity: granularity 1 settles every step,
# the default settles once per SuMSy period.

function gi_post_processing!(actor_data, model_data)
    rename!(actor_data, 3 => :deposit)

    return actor_data, model_data
end

function run_gi_only(granularity::Int; sumsy_interval::Int = 10, periods::Int = 3)
    sumsy = SuMSy(2000, 0, 0)
    model = create_sumsy_model(sumsy_interval = sumsy_interval,
                                granularity = granularity,
                                model_behaviors = process_model_sumsy!)
    population_params = FixedPopulationParams(population = 2,
                                                create_actor! = m -> create_sumsy_actor!(m,
                                                                                        sumsy = sumsy,
                                                                                        sumsy_interval = sumsy_interval,
                                                                                        initialize = false))
    monetary_params = StandardSuMSyParams(sumsy_interval = sumsy_interval,
                                            granularity = granularity,
                                            configure_sumsy_actors! = mixed_actors!,
                                            distribute_wealth! = m -> distribute_equal!(m, 0))
    data_handler = IntervalDataHandler(interval = sumsy_interval,
                                        actor_data_collectors = [deposit_collector],
                                        post_processing! = gi_post_processing!)

    return run_simulation(model,
                            sim_params = SimParams(periods * sumsy_interval),
                            population_params = population_params,
                            monetary_params = monetary_params,
                            transaction_params = BareBonesParams(nothing),
                            data_handler = data_handler)
end

@testset "SuMSy granularity - same guaranteed income per period" begin
    for granularity in [1, 2, 5, 10]
        actor_data, _ = run_gi_only(granularity)

        for group in groupby(actor_data, :id)
            @test group[!, :deposit] == Currency[0, 2000, 4000, 6000]
        end
    end
end

@testset "SuMSy granularity - settlement every granule" begin
    actor_data, _ = run_gi_only(1, sumsy_interval = 10, periods = 1)

    # Collected once per period, so only the start and the end are seen.
    @test actor_data[!, :deposit] == Currency[0, 0, 2000, 2000]

    model = create_sumsy_model(sumsy_interval = 10, granularity = 1, model_behaviors = process_model_sumsy!)
    actor = add_sumsy_actor!(model, sumsy = SuMSy(2000, 0, 0), initialize = false)
    run_econo_model!(model, 3)
    @test asset_value(get_balance(actor), SUMSY_DEP) == 600
end

@testset "SuMSy params - granularity checks" begin
    @test StandardSuMSyParams(sumsy_interval = 10,
                                configure_sumsy_actors! = mixed_actors!,
                                distribute_wealth! = m -> nothing).granularity == 10
    @test_throws ArgumentError StandardSuMSyParams(sumsy_interval = 10,
                                                    granularity = 11,
                                                    configure_sumsy_actors! = mixed_actors!,
                                                    distribute_wealth! = m -> nothing)
    @test_throws ArgumentError StandardSuMSyParams(sumsy_interval = 10,
                                                    granularity = 0,
                                                    configure_sumsy_actors! = mixed_actors!,
                                                    distribute_wealth! = m -> nothing)
end
