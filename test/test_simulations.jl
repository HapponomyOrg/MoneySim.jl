using Test
using EconoSim
using MoneySim
using Agents
using FixedPointDecimals

struct FixedIncome end
    
function deposit_income!(model::ABM)
    for actor in allagents(model)
        book_asset!(get_balance(actor), SUMSY_DEP, 100)
        actor.income += 100
    end
end

function initialize_behaviour_model!(model::ABM, params::FixedIncome)    
    add_model_behavior!(model, deposit_income!, position = 1)
end

@testset "wealth_distribution" begin
    num_actors = 10000

    model = create_econo_model(MonetaryActor{Currency, Balance{Currency}})

    sim_params = SimParams(MONTH)
    population_params = FixedPopulationParams(population = num_actors)

    monetary_params = FixedWealthParams(distribute_wealth! =
                                        m -> distribute_inequal!(m, MoneySim.get_wealth_inequality(BE, MoneySim.MONEY_STOCK)))
    tax_scheme =
        FixedTaxScheme(INCOME_TAX,
                        tax_recipients = num_actors,
                        tax_brackets = MoneySim.calculate_flat_gdp_tax(BE),
                        initial_income! =
                            a -> MoneySim.set_income!(a,
                                                        W_UNEQUAL,
                                                        MoneySim.get_gdp_per_capita(BE, period = MONTH),
                                                        MoneySim.overlap_adjusted_inequality_data(MoneySim.get_wealth_inequality(BE),
                                                                                            num_actors),
                                                        MoneySim.overlap_adjusted_inequality_data(MoneySim.get_income_inequality(BE,
                                                                                            period = MONTH, scale = IS_GDP),
                                                                                        num_actors)))

    MoneySim.initialize_simulation!(model,
                                    sim_params = sim_params,
                                    population_params = population_params,
                                    monetary_params = monetary_params,
                                    tax_scheme = tax_scheme)

    total_income = CUR_0

    for actor in allagents(model)
        total_income += actor.income
    end

    @test round(total_income) == round(MoneySim.get_gdp_per_capita(BE, period = MONTH) * num_actors)
end

@testset "Dem tax - SuMSy simulation" begin
    # sim_params = SimParams(30)
    # sumsy = SuMSy(1000, 0, 0.1, seed = 10)
    # sumsy_params = StandardSuMSyParams(sumsy_interval = MONTH,
    #                                     transactional = false,
    #                                     configure_sumsy_actors! = mixed_actors!,
    #                                     distribute_wealth! = m -> distribute_equal!(m, telo(sumsy)))
    # dem_taxes = FixedTaxScheme(tax_type = DEMURRAGE_TAX,
    #                             tax_recipients = 0,
    #                             tax_brackets = 0.1)
    # data_handler = IntervalDataHandler(interval = sumsy.interval,
    #                         actor_data_collectors = [deposit_collector,
    #                                                 income_collector!,
    #                                                 paid_tax_collector!],
    #                         model_data_collectors = [nagents, tax_collector!],
    #                         post_processing! = (x, y) -> (x, y))

    # data = run_sumsy_simulation(sumsy,
    #                             sumsy_params,
    #                             sim_params = sim_params,
    #                             population_params = FixedPopulationParams(1, create_sumsy_actor),
    #                             behaviour_params = FixedIncome(),
    #                             tax_scheme = dem_taxes,
    #                             data_handler = data_handler)

    # deposit = data[1][!, :deposit_collector]
    # income = data[1][!, :income_collector!]
    # paid_tax = data[1][!, :paid_tax_collector!]

    # @test length(deposit) == 4
    # @test length(income) == 4
    # @test length(paid_tax) == 4

    # @test deposit[1] == 10000
    # @test income[1] == 0
    # @test paid_tax[1] == 0

    # @test deposit[2] == 9910
    # @test income[2] == 1000
    # @test paid_tax[2] == 1100

    # @test deposit[3] == 9837.1
    # @test income[3] == 1000
    # @test paid_tax[3] == 1091
end

@testset "Dem tax + VAT - SuMSy simulation" begin
    # struct FixedTransactionParams end

    # function do_fake_transaction!(model::ABM)
    #     for actor in allagents(model)
    #         tax_scheme = model.tax_scheme
    #         tax_scheme.collect_vat!(actor, 10)
    #     end
    # end

    # function MoneySim.initialize_behaviour_model!(model::ABM, params::FixedTransactionParams)
    #     add_model_behavior!(model, do_fake_transaction!, position = 1)
    # end

    # sim_params = SimParams(30)
    # sumsy = SuMSy(1000, 0, 0.1, 1)
    # sumsy_params = StandardSuMSyParams(sumsy_interval = MONTH,
    #                                     transactional = false,
    #                                     configure_sumsy_actors! = mixed_actors!,
    #                                     distribute_wealth! = m -> distribute_equal!(m, telo(sumsy)))

    # data_handler = IntervalDataHandler(interval = sumsy.interval * 10,
    #                         actor_data_collectors = [deposit_collector,
    #                                                 income_collector!,
    #                                                 paid_tax_collector!,
    #                                                 paid_vat_collector!],
    #                         model_data_collectors = [nagents, tax_collector!, vat_collector!],
    #                         post_processing! = (x, y) -> (x, y))

    # data = run_sumsy_simulation(sumsy,
    #                             sumsy_params,
    #                             sim_params = sim_params,
    #                             population_params = FixedPopulationParams(1, create_sumsy_actor),
    #                             behaviour_params = FixedTransactionParams(),
    #                             tax_scheme = dem_taxes,
    #                             data_handler = data_handler)
end

@testset "Income tax - SuMSy simulation" begin
    # sim_params = SimParams(30)
    # sumsy = SuMSy(1000, 0, 0.1, 10)
    # sumsy_params = StandardSuMSyParams(sumsy_interval = MONTH,
    #                                     transactional = false,
    #                                     configure_sumsy_actors! = mixed_actors!,
    #                                     distribute_wealth! = m -> distribute_equal!(m, telo(sumsy)))
    # income_taxes = IncomeTaxScheme(0.1, 0, 1, (x, y) -> nothing, 10)
    # data_handler = IntervalDataHandler(interval = sumsy.interval,
    #                         actor_data_collectors = [deposit_collector,
    #                                                 income_collector!,
    #                                                 paid_tax_collector!],
    #                         model_data_collectors = [nagents, tax_collector!],
    #                         post_processing! = (x, y) -> (x, y))

    # data = run_sumsy_simulation(sumsy,
    #                             sumsy_params,
    #                             sim_params = sim_params,
    #                             population_params = FixedPopulationParams(1, create_sumsy_actor),
    #                             behaviour_params = FixedIncome(),
    #                             tax_scheme = income_taxes,
    #                             data_handler = data_handler)

    # deposit = data[1][!, :deposit_collector]
    # income = data[1][!, :income_collector!]
    # paid_tax = data[1][!, :paid_tax_collector!]

    # @test length(deposit) == 4
    # @test length(income) == 4
    # @test length(paid_tax) == 4

    # @test deposit[1] == 10000
    # @test income[1] == 0
    # @test paid_tax[1] == 0

    # @test deposit[2] == 10810
    # @test income[2] == 1000
    # @test paid_tax[2] == 100

    # @test deposit[3] == 11539
    # @test income[3] == 1000
    # @test paid_tax[3] == 100
end