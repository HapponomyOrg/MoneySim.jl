using EconoSim
using MoneySim
using DataFrames
using Test
using Agents

function reset_income!(model, add_gi_to_income::Bool)
    for actor in allagents(model)
        actor.income = CUR_0
        actor.expenses = CUR_0
        add_income!(actor, actor.tax_share)
        actor.tax_share = CUR_0

        if add_gi_to_income
            add_income!(actor, max(0, actor.gi - actor.dem))
        end
    end

    distribute_taxes!(model)
end

function create_passive_transaction_model(add_gi_to_income::Bool)
    return BareBonesParams(m -> reset_income!(m, add_gi_to_income))
end

function add_transaction_income!(model, add_gi_to_income::Bool, income::Real)
    reset_income!(model, add_gi_to_income)

    for actor in allagents(model)
        book_asset!(actor.balance, SUMSY_DEP, income)
        add_income!(actor, income)
    end
end

function create_active_transaction_model(income::Real, add_gi_to_income::Bool = false)
    return BareBonesParams(m -> add_transaction_income!(m, add_gi_to_income, income))
end

function post_data_processing!(actor_data, model_data)
    rename!(actor_data,
            5 => :taxed_income,
            6 => :income,
            7 => :expenses,
            8 => :paid_tax,
            9 => :paid_vat,
            10 => :tax_share,
            11 => :deposit)

    rename!(model_data,
            2 => :tax,
            3 => :vat)

    return actor_data, model_data
end

function create_data_handler(interval::Int = 1)
    return IntervalDataHandler(interval = interval,
                                actor_data_collectors = [:gi,
                                                            :dem,
                                                            taxed_amount_collector!,
                                                            income_collector!,
                                                            expenses_collector!,
                                                            paid_tax_collector!,
                                                            paid_vat_collector!,
                                                            :tax_share,
                                                            deposit_collector],
                                model_data_collectors = [tax_collector!,
                                                            vat_collector!],
                                post_processing! = post_data_processing!)
end

ad(data, symbol::Symbol, index::Int) = data[1][!, symbol][index]
md(data, symbol::Symbol, index::Int) = data[2][!, symbol][index]

@testset "Tax scheme - Income tax - SuMSy - GI not added to income" begin
    sumsy = SuMSy(2000, 0, 0.1)
    model = create_sumsy_model(sumsy_interval = 1,
                                model_behaviors = process_model_sumsy!)
    sim_params = SimParams(5)
    population_params = FixedPopulationParams(population = 1,   
                                                create_actor! = m -> create_sumsy_actor!(m,
                                                                                        sumsy = sumsy,
                                                                                        sumsy_interval = 1,
                                                                                        allow_negative_sumsy = true,
                                                                                        allow_negative_demurrage = false))
    monetary_params = StandardSuMSyParams(sumsy_interval = 1,
                                            transactional = false,
                                            configure_sumsy_actors! = m -> mixed_actors!(m, nagents(m)),
                                            distribute_wealth! = m -> distribute_equal!(m, telo(sumsy)))
    tax_scheme = FixedTaxScheme(INCOME_TAX,
                                tax_recipients = 1,
                                tax_interval = 1,
                                tax_brackets = 0.1)

    data = run_simulation(model,
                            sim_params = sim_params,
                            population_params = population_params,
                            monetary_params = monetary_params,
                            transaction_params = create_passive_transaction_model(false),
                            tax_scheme = tax_scheme,
                            data_handler = create_data_handler())
    
    @test sum(data[1][!, :paid_tax]) == 0
end

@testset "Tax scheme - Income tax - SuMSy - GI added to income - no net GI" begin
    sumsy = SuMSy(2000, 0, 0.1)
    model = create_sumsy_model(sumsy_interval = 1,
                                model_behaviors = process_model_sumsy!)
    sim_params = SimParams(5)
    population_params = FixedPopulationParams(population = 1,
                                                create_actor! = m -> create_sumsy_actor!(m,
                                                                                        sumsy = sumsy,
                                                                                        sumsy_interval = 1,
                                                                                        allow_negative_sumsy = true,
                                                                                        allow_negative_demurrage = false))
    monetary_params = StandardSuMSyParams(sumsy_interval = 1,
                                            transactional = false,
                                            configure_sumsy_actors! = m -> mixed_actors!(m, nagents(m)),
                                            distribute_wealth! = m -> distribute_equal!(m, telo(sumsy)))
    tax_scheme = FixedTaxScheme(INCOME_TAX,
                                tax_recipients = 1,
                                tax_interval = 1,
                                tax_brackets = 0.1)

    data = run_simulation(model,
                            sim_params = sim_params,
                            population_params = population_params,
                            monetary_params = monetary_params,
                            transaction_params = create_passive_transaction_model(true),
                            tax_scheme = tax_scheme,
                            data_handler = create_data_handler())
    
    @test sum(data[1][!, :paid_tax]) == 0
end

@testset "Tax scheme - Income tax - SuMSy - GI added to income - positive net GI - full distribution" begin
    sumsy = SuMSy(2000, 0, 0.1)
    model = create_sumsy_model(sumsy_interval = 1,
                                model_behaviors = process_model_sumsy!)
    sim_params = SimParams(5)
    population_params = FixedPopulationParams(population = 1,
                                                create_actor! = m -> create_sumsy_actor!(m,
                                                                                        sumsy = sumsy,
                                                                                        sumsy_interval = 1,
                                                                                        allow_negative_sumsy = true,
                                                                                        allow_negative_demurrage = false))
    monetary_params = StandardSuMSyParams(sumsy_interval = 1,
                                            transactional = false,
                                            configure_sumsy_actors! = m -> mixed_actors!(m, nagents(m)),
                                            distribute_wealth! = m -> distribute_equal!(m, 0))
    tax_scheme = FixedTaxScheme(INCOME_TAX,
                                tax_recipients = 1,
                                tax_interval = 1,
                                tax_brackets = 0.1)

    data = run_simulation(model,
                            sim_params = sim_params,
                            population_params = population_params,
                            monetary_params = monetary_params,
                            transaction_params = create_passive_transaction_model(true),
                            tax_scheme = tax_scheme,
                            data_handler = create_data_handler())
    
    for i in 2:size(data[1])[1]
        @test ad(data, :gi, i) - ad(data, :dem, i) + ad(data, :tax_share, i - 1) == ad(data, :taxed_income, i)
    end

    model = create_sumsy_model(sumsy_interval = 1,
                                model_behaviors = process_model_sumsy!)

    sim_params = SimParams(50)
    tax_scheme = FixedTaxScheme(INCOME_TAX,
                                tax_recipients = 1,
                                tax_interval = 10,
                                tax_brackets = 0.1) 

    data = run_simulation(model,
                            sim_params = sim_params,
                            population_params = population_params,
                            monetary_params = monetary_params,
                            transaction_params = create_passive_transaction_model(true),
                            tax_scheme = tax_scheme,
                            data_handler = create_data_handler(10))
    
    @test md(data, :tax, 1) == 0
    @test md(data, :tax, 2) == 1302.6431
    
    for i in 2:size(data[1])[1]
        @test ad(data, :income, i) + ad(data, :tax_share, i - 1) == ad(data, :taxed_income, i)
    end
end

@testset "Tax scheme - Income tax - SuMSy - GI added to income - positive net GI - no distribution" begin
    sumsy = SuMSy(2000, 0, 0.1)
    model = create_sumsy_model(sumsy_interval = 1,
                                model_behaviors = process_model_sumsy!)
    sim_params = SimParams(5)
    population_params = FixedPopulationParams(population = 1,
                                                create_actor! = m -> create_sumsy_actor!(m,
                                                                                        sumsy = sumsy,
                                                                                        sumsy_interval = 1,
                                                                                        allow_negative_sumsy = true,
                                                                                        allow_negative_demurrage = false))
    monetary_params = StandardSuMSyParams(sumsy_interval = 1,
                                            transactional = false,
                                            configure_sumsy_actors! = m -> mixed_actors!(m, nagents(m)),
                                            distribute_wealth! = m -> distribute_equal!(m, 0))
    tax_scheme = FixedTaxScheme(INCOME_TAX,
                                tax_recipients = 0,
                                tax_interval = 1,
                                tax_brackets = 0.1)

    data = run_simulation(model,
                            sim_params = sim_params,
                            population_params = population_params,
                            monetary_params = monetary_params,
                            transaction_params = create_passive_transaction_model(true),
                            tax_scheme = tax_scheme,
                            data_handler = create_data_handler())
    
    @test md(data, :tax, 1) == 0
    @test md(data, :tax, 2) == 200
    @test md(data, :tax, 3) == 182
    @test md(data, :tax, 4) == 165.62
    @test md(data, :tax, 5) == 150.7142
    @test md(data, :tax, 6) == 137.1499

    model = create_sumsy_model(sumsy_interval = 1,
                                model_behaviors = process_model_sumsy!)

    sim_params = SimParams(50)
    tax_scheme = FixedTaxScheme(INCOME_TAX,
                                tax_recipients = 0,
                                tax_interval = 10,
                                tax_brackets = 0.1)

    data = run_simulation(model,
                            sim_params = sim_params,
                            population_params = population_params,
                            monetary_params = monetary_params,
                            transaction_params = create_passive_transaction_model(true),
                            tax_scheme = tax_scheme,
                            data_handler = create_data_handler(10))
    
    @test md(data, :tax, 1) == 0
    @test md(data, :tax, 2) == 1302.6431

    for i in 2:size(data[1])[1]
        @test Currency(calculate_sumsy_deposit(sumsy, 10, ad(data, :deposit, i - 1))) - ad(data, :paid_tax, i) == ad(data, :deposit, i)
    end
end

@testset "Tax Scheme - Demurrage tax" begin
end

@testset "Tax scheme - VAT tax - No SuMSy - no distribution" begin
    # VAT interval = 1
    model = create_econo_model()
    sim_params = SimParams(5)
    population_params = FixedPopulationParams(population = 1,
                                                create_actor! = m -> create_monetary_actor!(m,
                                                                                        allow_negative_assets = true))
    monetary_params = FixedWealthParams(m -> distribute_equal!(m, 10000))
    tax_scheme = FixedTaxScheme(VAT_ONLY,
                                tax_recipients = 0,
                                vat_interval = 1,
                                vat = 0.1)

    data = run_simulation(model,
                            sim_params = sim_params,
                            population_params = population_params,
                            monetary_params = monetary_params,
                            transaction_params = create_active_transaction_model(1000),
                            tax_scheme = tax_scheme,
                            data_handler = create_data_handler())

    @test sum(data[1][!, :paid_vat]) == 500

    # VAT interval = 10
    model = create_econo_model()
    sim_params = SimParams(50)
    tax_scheme = FixedTaxScheme(VAT_ONLY,
                                tax_recipients = 0,
                                vat_interval = 10,
                                vat = 0.1)

    data = run_simulation(model,
                            sim_params = sim_params,
                            population_params = population_params,
                            monetary_params = monetary_params,
                            transaction_params = create_active_transaction_model(1000),
                            tax_scheme = tax_scheme,
                            data_handler = create_data_handler(10))

    @test sum(data[1][!, :paid_vat]) == 5000
end

@testset "Tax scheme - VAT tax - No SuMSy - distribution" begin
    # VAT interval = 1
    model = create_econo_model()
    sim_params = SimParams(5)
    population_params = FixedPopulationParams(population = 1,
                                                create_actor! = m -> create_monetary_actor!(m,
                                                                                        allow_negative_assets = true))
    monetary_params = FixedWealthParams(m -> distribute_equal!(m, 10000))
    tax_scheme = FixedTaxScheme(VAT_ONLY,
                                tax_recipients = 1,
                                vat_interval = 1,
                                vat = 0.1)

    data = run_simulation(model,
                            sim_params = sim_params,
                            population_params = population_params,
                            monetary_params = monetary_params,
                            transaction_params = create_active_transaction_model(1000),
                            tax_scheme = tax_scheme,
                            data_handler = create_data_handler())
    
    @test ad(data, :income, 1) == 0
    @test ad(data, :income, 2) == 1000

    for i in 2:size(data[1])[1]
        ad(data, :deposit, i) == ad(data, :deposit, i - 1) + ad(data, :income, i) - ad(data, :paid_vat, i)
    end

    @test ad(data, :paid_vat, 1) == 0
    @test ad(data, :paid_vat, 2) == 100
    @test ad(data, :paid_vat, 3) == 110
    @test ad(data, :paid_vat, 4) == 111
    @test ad(data, :paid_vat, 5) == 111.1
    @test ad(data, :paid_vat, 6) == 111.11

    # VAT interval = 10
    model = create_econo_model()
    sim_params = SimParams(50)
    tax_scheme = FixedTaxScheme(VAT_ONLY,
                                tax_recipients = 1,
                                vat_interval = 10,
                                vat = 0.1)

    data = run_simulation(model,
                            sim_params = sim_params,
                            population_params = population_params,
                            monetary_params = monetary_params,
                            transaction_params = create_active_transaction_model(1000),
                            tax_scheme = tax_scheme,
                            data_handler = create_data_handler(10))
    
    @test ad(data, :income, 1) == 0
    @test ad(data, :income, 2) == 10000

    for i in 2:size(data[1])[1]
        ad(data, :deposit, i) == ad(data, :deposit, i - 1) + ad(data, :income, i) - ad(data, :paid_vat, i)
    end

    @test ad(data, :paid_vat, 1) == 0
    @test ad(data, :paid_vat, 2) == 1000
    @test ad(data, :paid_vat, 3) == 1100
    @test ad(data, :paid_vat, 4) == 1110
    @test ad(data, :paid_vat, 5) == 1111
    @test ad(data, :paid_vat, 6) == 1111.1
end

@testset "Tax scheme - Income tax + VAT - No SuMSy - distribution" begin
    # Tax interval = 1, VAT interval = 1
    model = create_econo_model()
    sim_params = SimParams(5)
    population_params = FixedPopulationParams(population = 1,
                                                create_actor! = m -> create_monetary_actor!(m,
                                                                                        allow_negative_assets = true))
    monetary_params = FixedWealthParams(m -> distribute_equal!(m, 10000))
    tax_scheme = FixedTaxScheme(INCOME_TAX,
                                tax_recipients = 1,
                                tax_interval = 1,
                                tax_brackets = 0.1,
                                vat_interval = 1,
                                vat = 0.1)

    data = run_simulation(model,
                            sim_params = sim_params,
                            population_params = population_params,
                            monetary_params = monetary_params,
                            transaction_params = create_active_transaction_model(1000),
                            tax_scheme = tax_scheme,
                            data_handler = create_data_handler())
    
    @test ad(data, :income, 1) == 0
    @test ad(data, :income, 2) == 1000

    for i in 2:size(data[1])[1]
        ad(data, :deposit, i) == ad(data, :deposit, i - 1) + ad(data, :income, i) - ad(data, :paid_tax, i) - ad(data, :paid_vat, i)
        ad(data, :taxed_income, i) == ad(data, :income, i) - ad(data, :paid_vat, i)
    end

    # Tax interval = 10, VAT interval = 10
    model = create_econo_model()
    sim_params = SimParams(50)
    tax_scheme = FixedTaxScheme(INCOME_TAX,
                                tax_recipients = 1,
                                tax_interval = 10,
                                tax_brackets = 0.1,
                                vat_interval = 10,
                                vat = 0.1)

    data = run_simulation(model,
                            sim_params = sim_params,
                            population_params = population_params,
                            monetary_params = monetary_params,
                            transaction_params = create_active_transaction_model(1000),
                            tax_scheme = tax_scheme,
                            data_handler = create_data_handler(10))
    
    @test ad(data, :income, 1) == 0
    @test ad(data, :income, 2) == 10000

    for i in 2:size(data[1])[1]
        ad(data, :deposit, i) == ad(data, :deposit, i - 1) + ad(data, :income, i) - ad(data, :paid_tax, i) - ad(data, :paid_vat, i)
        ad(data, :taxed_income, i) == ad(data, :income, i) - ad(data, :paid_vat, i)
    end

     # Tax interval = 10, VAT interval = 5
     model = create_econo_model()
     sim_params = SimParams(50)
     tax_scheme = FixedTaxScheme(INCOME_TAX,
                                 tax_recipients = 1,
                                 tax_interval = 10,
                                 tax_brackets = 0.1,
                                 vat_interval = 5,
                                 vat = 0.1)
 
     data = run_simulation(model,
                             sim_params = sim_params,
                             population_params = population_params,
                             monetary_params = monetary_params,
                             transaction_params = create_active_transaction_model(1000),
                             tax_scheme = tax_scheme,
                             data_handler = create_data_handler(10))
     
     @test ad(data, :income, 1) == 0
     @test ad(data, :income, 2) == 10500
 
    for i in 2:size(data[1])[1]
        ad(data, :deposit, i) == ad(data, :deposit, i - 1) + ad(data, :income, i) - ad(data, :paid_tax, i) - ad(data, :paid_vat, i)
        ad(data, :taxed_income, i) == ad(data, :income, i) - ad(data, :paid_vat, i)
    end
end

@testset "Tax scheme - Vat tax - SuMSy - standaerd yard sale - no distribution" begin
    sumsy = SuMSy(2000, 0, 0.1)
    model = create_sumsy_model(sumsy_interval = 1,
                                model_behaviors = process_model_sumsy!)
    sim_params = SimParams(50)
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
    transaction_params = StandardYardSaleParams(1:1,
                                                0.1:0.1:0.1,
                                                0,
                                                false)
    tax_scheme = FixedTaxScheme(VAT_ONLY,
                                tax_recipients = 0,
                                tax_interval = 1,
                                vat = 0.1)

    data = run_simulation(model,
                            sim_params = sim_params,
                            population_params = population_params,
                            monetary_params = monetary_params,
                            transaction_params = transaction_params,
                            tax_scheme = tax_scheme,
                            data_handler = create_data_handler())

    time_groups = groupby(data[1], :time)

    for group in time_groups
        @test sum(group[!, :paid_vat]) == Currency(0.1 * sum(group[!, :income]))
    end

    id_groups = groupby(data[1], :id)

    for i in 1:size(id_groups[1])[1]
        @test id_groups[1][!, :income][i] == id_groups[2][!, :expenses][i]
    end
end