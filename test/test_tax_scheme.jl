using EconoSim
using MoneySim
using DataFrames
using Test
using Agents

# Rewritten on 2026-11-11 against StateTaxScheme. The former tests used FixedTaxScheme, distribute_taxes! and
# per-actor gi/dem/tax_share fields, which no longer exist and are not brought back.
#
# Order within a step: SuMSy settlement, then the tax scheme (register income, calculate tax, collect VAT,
# collect and redistribute tax), then the transaction model. Income booked in step t is therefore taxed from step t + 1.

function tax_post_processing!(actor_data, model_data)
    rename!(actor_data,
            3 => :taxed_amount,
            4 => :income,
            5 => :paid_tax,
            6 => :paid_vat,
            7 => :tax_share,
            8 => :vat_share,
            9 => :deposit)

    rename!(model_data,
            2 => :tax,
            3 => :vat,
            4 => :debt)

    return actor_data, model_data
end

function tax_data_handler(interval::Int = 1)
    return IntervalDataHandler(interval = interval,
                                actor_data_collectors = [taxed_amount_collector!,
                                                        income_collector!,
                                                        paid_tax_collector!,
                                                        paid_vat_collector!,
                                                        MoneySim.tax_share_collector!,
                                                        MoneySim.vat_share_collector!,
                                                        deposit_collector],
                                model_data_collectors = [tax_collector!,
                                                        vat_collector!,
                                                        debt_collector],
                                post_processing! = tax_post_processing!)
end

function earn!(model::ABM, income::Real)
    for actor in allagents(model)
        actor.income = CUR_0
        actor.expenses = CUR_0
        book_asset!(get_balance(actor), SUMSY_DEP, income)
        add_income!(actor, income)
    end
end

earning(income::Real) = BareBonesParams(m -> earn!(m, income))

function flat_tax_scheme(tax_type::TAX_TYPE;
                            tax_rate::Real = 0,
                            vat::Real = 0,
                            tax_recipients::Int = 0,
                            interval::Int = 1,
                            redistribution_interval::Int = interval,
                            vat_interval::Int = interval,
                            projected_expenses::Real = 0,
                            deficit_spending::Bool = false)
    return StateTaxScheme(tax_type,
                            tax_recipients = tax_recipients,
                            tax_calculation_interval = interval,
                            tax_redistribution_interval = redistribution_interval,
                            get_tax_brackets = (_, _) -> tax_rate,
                            vat_interval = vat_interval,
                            get_vat = (_, _) -> vat,
                            get_projected_expenses = (_, _) -> projected_expenses,
                            deficit_spending = deficit_spending,
                            debt_reduction = _ -> 0)
end

function run_fixed_wealth(tax_scheme; steps::Int = 5, wealth::Real = 10000, income::Real = 1000, population::Int = 1)
    model = create_econo_model(MonetaryActor{Currency, Balance{Currency}})
    population_params = FixedPopulationParams(population = population,
                                                create_actor! = m -> create_monetary_actor!(m, allow_negative_assets = true))

    return run_simulation(model,
                            sim_params = SimParams(steps),
                            population_params = population_params,
                            monetary_params = FixedWealthParams(distribute_wealth! = m -> distribute_equal!(m, wealth)),
                            transaction_params = earning(income),
                            tax_scheme = tax_scheme,
                            data_handler = tax_data_handler())
end

@testset "Tax scheme - Income tax - no income" begin
    actor_data, model_data = run_fixed_wealth(flat_tax_scheme(INCOME_TAX, tax_rate = 0.1), income = 0)

    @test sum(actor_data[!, :paid_tax]) == 0
    @test all(actor_data[!, :deposit] .== 10000)
end

@testset "Tax scheme - Income tax - flat 10%, every step, no distribution" begin
    actor_data, model_data = run_fixed_wealth(flat_tax_scheme(INCOME_TAX, tax_rate = 0.1))

    # Steps 0..5. Income from step t is taxed in step t + 1.
    @test actor_data[!, :income] == Currency[0, 1000, 1000, 1000, 1000, 1000]
    @test actor_data[!, :paid_tax] == Currency[0, 0, 100, 100, 100, 100]
    @test model_data[!, :tax] == Currency[0, 0, 100, 100, 100, 100]
    @test actor_data[!, :deposit][end] == 10000 + 5 * 1000 - 4 * 100
end

@testset "Tax scheme - Income tax - full distribution" begin
    actor_data, model_data = run_fixed_wealth(flat_tax_scheme(INCOME_TAX, tax_rate = 0.1, tax_recipients = 1))

    @test actor_data[!, :paid_tax] == Currency[0, 0, 100, 100, 100, 100]
    @test actor_data[!, :tax_share] == actor_data[!, :paid_tax]
    @test actor_data[!, :deposit][end] == 10000 + 5 * 1000
end

@testset "Tax scheme - Income tax - deficit spending" begin
    tax_scheme = flat_tax_scheme(INCOME_TAX,
                                    tax_rate = 0.1,
                                    tax_recipients = 1,
                                    projected_expenses = 150,
                                    deficit_spending = true)
    actor_data, model_data = run_fixed_wealth(tax_scheme)

    # Each collection pays out the projected expenses; the gap with the collected tax is added to the debt.
    @test actor_data[!, :tax_share] == Currency[0, 150, 150, 150, 150, 150]
    @test model_data[!, :debt][end] == 150 + 4 * 50
end

@testset "Tax scheme - Income tax - collection over a longer period" begin
    # Taxes calculated every 10 steps and collected once per period should collect the full tax.
    tax_scheme = flat_tax_scheme(INCOME_TAX, tax_rate = 0.1, interval = 10)
    actor_data, _ = run_fixed_wealth(tax_scheme, steps = 30)
    paid = sum(actor_data[!, :paid_tax])

    # Known defect KG-m23-14: each collection takes tax_to_pay / (calculation interval - collections done),
    # which counts steps, not collections. With one collection per period only 1/10 of the tax is collected
    # and the rest is overwritten at the next calculation.
    # Tax is calculated at steps 1, 11 and 21 on the income registered since the last calculation:
    # 0, then 10 steps of 1000 twice.
    @test_broken paid == Currency(0.1 * 1000 * 20)
    @test paid == Currency(0.1 * 1000 * 20 / 10)

    # Collecting every step spreads the tax over the period and collects it in full.
    tax_scheme = flat_tax_scheme(INCOME_TAX, tax_rate = 0.1, interval = 10, redistribution_interval = 1)
    actor_data, _ = run_fixed_wealth(tax_scheme, steps = 30)
    @test sum(actor_data[!, :paid_tax][1:21]) == Currency(0.1 * 1000 * 10) # tax calculated at step 11, collected in steps 11..20
end

@testset "Tax scheme - Demurrage tax" begin
    sumsy = SuMSy(0, 0, 0)
    model = create_sumsy_model(sumsy_interval = 1, model_behaviors = process_model_sumsy!)
    population_params = FixedPopulationParams(population = 1,
                                                create_actor! = m -> create_sumsy_actor!(m,
                                                                                        sumsy = sumsy,
                                                                                        sumsy_interval = 1,
                                                                                        initialize = false))
    monetary_params = StandardSuMSyParams(sumsy_interval = 1,
                                            configure_sumsy_actors! = mixed_actors!,
                                            distribute_wealth! = m -> distribute_equal!(m, 10000))

    actor_data, _ = run_simulation(model,
                                    sim_params = SimParams(5),
                                    population_params = population_params,
                                    monetary_params = monetary_params,
                                    transaction_params = BareBonesParams(nothing),
                                    tax_scheme = flat_tax_scheme(DEMURRAGE_TAX, tax_rate = 0.1),
                                    data_handler = tax_data_handler())

    # 10% of the balance above the demurrage-free amount (0) every step.
    @test actor_data[!, :paid_tax] == Currency[0, 1000, 900, 810, 729, 656.1]
    @test actor_data[!, :deposit][end] == Currency(10000 * 0.9^5)
end

@testset "Tax scheme - VAT - no distribution" begin
    actor_data, model_data = run_fixed_wealth(flat_tax_scheme(VAT_ONLY, vat = 0.1))
    vat = Currency(1000 * 0.1 / 1.1)

    # VAT is taken as included in the income: rate / (1 + rate) of it.
    # (The former test expected rate * income; see KG-m23 in the knowledge base.)
    @test actor_data[!, :paid_vat] == [CUR_0, CUR_0, vat, vat, vat, vat]
    @test model_data[!, :vat] == actor_data[!, :paid_vat]
    @test sum(actor_data[!, :paid_tax]) == 0
    @test actor_data[!, :deposit][end] == 10000 + 5 * 1000 - 4 * vat
end

@testset "Tax scheme - VAT - distribution" begin
    actor_data, _ = run_fixed_wealth(flat_tax_scheme(VAT_ONLY, vat = 0.1, tax_recipients = 1))

    @test actor_data[!, :vat_share] == actor_data[!, :paid_vat]
    @test actor_data[!, :deposit][end] == 10000 + 5 * 1000
end

@testset "Tax scheme - Income tax + VAT - distribution" begin
    tax_scheme = flat_tax_scheme(INCOME_TAX, tax_rate = 0.1, vat = 0.1, tax_recipients = 1)
    actor_data, _ = run_fixed_wealth(tax_scheme)
    vat = Currency(1000 * 0.1 / 1.1)

    @test actor_data[!, :paid_tax] == Currency[0, 0, 100, 100, 100, 100]
    @test actor_data[!, :paid_vat] == [CUR_0, CUR_0, vat, vat, vat, vat]
    @test actor_data[!, :deposit][end] == 10000 + 5 * 1000

    for i in 2:nrow(actor_data)
        @test actor_data[!, :deposit][i] == actor_data[!, :deposit][i - 1] +
                                                actor_data[!, :income][i] -
                                                actor_data[!, :paid_tax][i] -
                                                actor_data[!, :paid_vat][i] +
                                                actor_data[!, :tax_share][i] +
                                                actor_data[!, :vat_share][i]
    end
end

@testset "Tax scheme - VAT - SuMSy - standard yard sale - no distribution" begin
    sumsy = SuMSy(2000, 0, 0.1)
    model = create_sumsy_model(sumsy_interval = 1, model_behaviors = process_model_sumsy!)
    population_params = FixedPopulationParams(population = 2,
                                                create_actor! = m -> create_sumsy_actor!(m,
                                                                                        sumsy = sumsy,
                                                                                        sumsy_interval = 1,
                                                                                        allow_negative_sumsy = true,
                                                                                        allow_negative_demurrage = false))
    monetary_params = StandardSuMSyParams(sumsy_interval = 1,
                                            configure_sumsy_actors! = m -> mixed_actors!(m, num_gi_actors = nagents(m)),
                                            distribute_wealth! = m -> distribute_equal!(m, telo(sumsy)))
    transaction_params = StandardYardSaleParams(transaction_range = 1:1,
                                                wealth_transfer_range = 0.1:0.1:0.1,
                                                average_wealth = telo(sumsy))

    actor_data, _ = run_simulation(model,
                                    sim_params = SimParams(50),
                                    population_params = population_params,
                                    monetary_params = monetary_params,
                                    transaction_params = transaction_params,
                                    tax_scheme = flat_tax_scheme(VAT_ONLY, vat = 0.1),
                                    data_handler = tax_data_handler())

    # Each actor pays VAT in step t on the income it earned in step t - 1.
    for group in groupby(actor_data, :id)
        for i in 2:nrow(group)
            @test group[!, :paid_vat][i] == Currency(group[!, :income][i - 1] * 0.1 / 1.1)
        end
    end

    # One trade per step: what one actor earns, the other spends.
    time_groups = groupby(actor_data, :time)
    @test all(g -> sum(g[!, :income]) == maximum(g[!, :income]), time_groups)
end

@testset "Scale taxes - raise to target revenue" begin
    tax_base = Vector{Currency}([100032953.0587, 47835517.5256, 105421842.0211, 152142535.1119, 422081130.4976])
    tax_brackets = make_tiers(MoneySim.get_income_tax_brackets(BE))
    projected_revenue = MoneySim.calculate_revenue(tax_base, tax_brackets)
    target_revenue = Currency(projected_revenue * 1.2)

    scaled_brackets, tax_scale = MoneySim.scale_brackets(tax_base, tax_brackets, target_revenue)

    @test tax_scale == round(target_revenue / projected_revenue, digits = 2)
    @test MoneySim.calculate_revenue(tax_base, scaled_brackets) > projected_revenue
    @test isapprox(MoneySim.calculate_revenue(tax_base, scaled_brackets), target_revenue, rtol = 0.05)
end

@testset "Scale taxes - lower to target revenue" begin
    tax_base = Vector{Currency}([100032953.0587, 47835517.5256, 105421842.0211, 152142535.1119, 422081130.4976])
    tax_brackets = make_tiers(MoneySim.get_income_tax_brackets(BE))
    projected_revenue = MoneySim.calculate_revenue(tax_base, tax_brackets)
    target_revenue = Currency(projected_revenue / 2)

    scaled_brackets, tax_scale = MoneySim.scale_brackets(tax_base, tax_brackets, target_revenue)

    @test tax_scale == 0.5
    # Known defect: scale_brackets only ever raises rates. It reports the lower scale but returns the brackets unchanged.
    @test_broken MoneySim.calculate_revenue(tax_base, scaled_brackets) == target_revenue
    @test MoneySim.calculate_revenue(tax_base, scaled_brackets) == projected_revenue
end

@testset "Create tax base" begin
    tax_brackets = make_tiers([(0, 0), (500, 0.25), (2000, 0.5)])
    tax_base = MoneySim.create_tax_base([1], tax_brackets, a -> 10000)

    @test tax_base == Currency[500, 1500, 8000]
    @test MoneySim.calculate_revenue(tax_base, tax_brackets) == 0.25 * 1500 + 0.5 * 8000
end
