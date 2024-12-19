using Test
using EconoSim
using MoneySim
using Agents
using FixedPointDecimals

struct FixedIncome <: BehaviourParams{Currency} end
    
function deposit_income!(model::ABM)
    for actor in allagents(model)
        book_asset!(get_balance(actor), SUMSY_DEP, 100)
        actor.income += 100
    end
end

function MoneySim.initialize_behaviour_model!(model::ABM, params::FixedIncome)    
    add_model_behavior!(model, deposit_income!, position = 1)
end

@testset "General Simulation - barebones" begin
    
end

@testset "Dem tax - SuMSy simulation" begin
    sim_params = SimParams(30)
    sumsy = SuMSy(1000, 0, 0.1, 10)
    sumsy_params = StandardSuMSyParams(telo(sumsy),
                                        telo(sumsy),
                                        configure_sumsy_actors! = mixed_actors!,
                                        distribute_wealth! = equal_wealth_distribution!)
    dem_taxes = DemurrageTaxScheme(0.1, 0, 1, (x, y) -> nothing, 10)
    data_handler = IntervalDataHandler(interval = sumsy.interval,
                            actor_data_collectors = [deposit_collector,
                                                    income_collector!,
                                                    paid_tax_collector!],
                            model_data_collectors = [nagents, tax_collector!],
                            post_processing! = (x, y) -> (x, y))

    data = run_sumsy_simulation(sumsy,
                                sumsy_params,
                                sim_params = sim_params,
                                population_params = FixedPopulationParams(1, create_sumsy_actor),
                                behaviour_params = FixedIncome(),
                                tax_scheme = dem_taxes,
                                data_handler = data_handler)

    deposit = data[1][!, :deposit_collector]
    income = data[1][!, :income_collector!]
    paid_tax = data[1][!, :paid_tax_collector!]

    @test length(deposit) == 4
    @test length(income) == 4
    @test length(paid_tax) == 4

    @test deposit[1] == 10000
    @test income[1] == 0
    @test paid_tax[1] == 0

    @test deposit[2] == 9910
    @test income[2] == 1000
    @test paid_tax[2] == 1100

    @test deposit[3] == 9837.1
    @test income[3] == 1000
    @test paid_tax[3] == 1091
end

@testset "Dem tax + VAT - SuMSy simulation" begin
    struct FixedTransactionParams <: BehaviourParams{Currency} end

    function do_fake_transaction!(model::ABM)
        for actor in allagents(model)
            tax_scheme = model.tax_scheme
            tax_scheme.collect_vat!(actor, 10)
        end
    end

    function MoneySim.initialize_behaviour_model!(model::ABM, params::FixedTransactionParams)
        add_model_behavior!(model, do_fake_transaction!, position = 1)
    end

    sim_params = SimParams(30)
    sumsy = SuMSy(1000, 0, 0.1, 1)
    sumsy_params = StandardSuMSyParams(telo(sumsy),
                                        telo(sumsy),
                                        configure_sumsy_actors! = mixed_actors!,
                                        distribute_wealth! = equal_wealth_distribution!)
    dem_taxes = DemurrageTaxScheme(0.1, 0, 1, (x, y) -> nothing, 10, vat = 0.1)

    data_handler = IntervalDataHandler(interval = sumsy.interval * 10,
                            actor_data_collectors = [deposit_collector,
                                                    income_collector!,
                                                    paid_tax_collector!,
                                                    paid_vat_collector!],
                            model_data_collectors = [nagents, tax_collector!, vat_collector!],
                            post_processing! = (x, y) -> (x, y))

    data = run_sumsy_simulation(sumsy,
                                sumsy_params,
                                sim_params = sim_params,
                                population_params = FixedPopulationParams(1, create_sumsy_actor),
                                behaviour_params = FixedTransactionParams(),
                                tax_scheme = dem_taxes,
                                data_handler = data_handler)
end

@testset "Income tax - SuMSy simulation" begin
    sim_params = SimParams(30)
    sumsy = SuMSy(1000, 0, 0.1, 10)
    sumsy_params = StandardSuMSyParams(telo(sumsy),
                                        telo(sumsy),
                                        configure_sumsy_actors! = mixed_actors!,
                                        distribute_wealth! = equal_wealth_distribution!)
    income_taxes = IncomeTaxScheme(0.1, 0, 1, (x, y) -> nothing, 10)
    data_handler = IntervalDataHandler(interval = sumsy.interval,
                            actor_data_collectors = [deposit_collector,
                                                    income_collector!,
                                                    paid_tax_collector!],
                            model_data_collectors = [nagents, tax_collector!],
                            post_processing! = (x, y) -> (x, y))

    data = run_sumsy_simulation(sumsy,
                                sumsy_params,
                                sim_params = sim_params,
                                population_params = FixedPopulationParams(1, create_sumsy_actor),
                                behaviour_params = FixedIncome(),
                                tax_scheme = income_taxes,
                                data_handler = data_handler)

    deposit = data[1][!, :deposit_collector]
    income = data[1][!, :income_collector!]
    paid_tax = data[1][!, :paid_tax_collector!]

    @test length(deposit) == 4
    @test length(income) == 4
    @test length(paid_tax) == 4

    @test deposit[1] == 10000
    @test income[1] == 0
    @test paid_tax[1] == 0

    @test deposit[2] == 10810
    @test income[2] == 1000
    @test paid_tax[2] == 100

    @test deposit[3] == 11539
    @test income[3] == 1000
    @test paid_tax[3] == 100
end