using EconoSim
using MoneySim
using DataFrames

@enum PopulationType P_FIXED P_DEMOGRAPHIC
@enum MonetaryType M_FIXED M_SUMSY M_DEBT_BASED
@enum WealthDistribution W_EQUAL W_UNEQUAL
@enum Taxes T_NO_TAX T_INCOME_TAX T_DEM_TAX T_GDP_FLAT_TAX T_VAT_ONLY

set_currency_precision!(4)

function post_process_sim_data!(actor_data,
                                model_data,
                                sumsy_sim::Bool = false)
    rename!(actor_data,
            3 => :deposit,
            4 => :equity,
            5 => :income,
            6 => :expenses,
            7 => :paid_tax,
            8 => :paid_vat,
            9 => :tax_share,
            10 => :vat_share)

    rename!(model_data,
            2 => :num_actors,
            3 => :gdp,
            4 => :transactions,
            5 => :min_transaction,
            6 => :max_transaction,
            7 => :collected_tax,
            8 => :failed_tax,
            9 => :collected_vat,
            10 => :failed_vat,
            11 => :debt)

    if sumsy_sim
        rename!(actor_data,
                11 => :gi,
                12 => :demurrage
        )
        rename!(model_data,
                12 => :total_gi,
                13 => :total_demurrage)
    end

    return actor_data, model_data
end

function post_process_no_tax_sim_data!(actor_data,
                                        model_data,
                                        sumsy_sim::Bool = false)
    rename!(actor_data,
            3 => :deposit,
            4 => :equity,
            5 => :income,
            6 => :expenses)

    rename!(model_data,
            2 => :num_actors,
            3 => :gdp,
            4 => :transactions,
            5 => :min_transaction,
            6 => :max_transaction)

    if sumsy_sim
        rename!(actor_data,
                7 => :gi,
                8 => :demurrage
        )
        rename!(model_data,
                7 => :total_gi,
                8 => :total_demurrage)
    end

    return actor_data, model_data
end

function reset_gi!(model::ABM)
    for actor in allagents(model)
        actor.gi = CUR_0
        actor.dem = CUR_0
    end
end

function overlap_adjusted_inequality_data(inequality_data::InequalityData,
                                            num_actors::Int)
    bottom_0_1, bottom_1, bottom_10, top_10, top_1, top_0_1 = adjust_for_overlap(inequality_data, num_actors)

    return InequalityData(top_0_1,
                            top_1,
                            top_10,
                            inequality_data.high_middle_40,
                            inequality_data.low_middle_40,
                            bottom_10,
                            bottom_1,
                            bottom_0_1)
end

function set_income!(actor::AbstractBalanceActor,
                    wealth_distribution::WealthDistribution,
                    gdp_per_capita::Currency,
                    wealth_inequality::InequalityData,
                    income_inequality::InequalityData)
    if wealth_distribution == W_EQUAL
        actor.income = gdp_per_capita
    elseif wealth_distribution == W_UNEQUAL
        wealth = asset_value(get_balance(actor), SUMSY_DEP)

        if wealth == wealth_inequality.top_0_1
            actor.income = income_inequality.top_0_1
        elseif wealth == wealth_inequality.top_1
            actor.income = income_inequality.top_1
        elseif wealth == wealth_inequality.top_10
            actor.income = income_inequality.top_10
        elseif wealth == wealth_inequality.high_middle_40
            actor.income = income_inequality.high_middle_40
        elseif wealth == wealth_inequality.low_middle_40
            actor.income = income_inequality.low_middle_40
        elseif wealth == wealth_inequality.bottom_10
            actor.income = income_inequality.bottom_10
        elseif wealth == wealth_inequality.bottom_1
            actor.income = income_inequality.bottom_1
        elseif wealth == wealth_inequality.bottom_0_1
            actor.income = income_inequality.bottom_0_1
        end
    end

    actor.data_income = actor.income
end

"""
    adjust_tax_distribution!(model::ABM,
                            distribution_type::DistributionType,
                            amount::Real)

    Adjusts the amount to distribute to be in line with actual government expenses.
    Records accumulated government debt.
"""
function adjust_tax_distribution!(model::ABM,
                                    distribution_type::DistributionType,
                                    amount::Real)
    if distribution_type == D_TAX
        country = model.country
        full_expenses = get_net_expenses_per_capita(country) * nagents(model)
        gap = full_expenses - amount
        model.accumulated_debt += gap

        return max(amount, full_expenses)
    else
        return amount
    end
end

function simulate_country(country::Country;
                            sim_length = 100 * YEAR,
                            data_collection_interval::Int = YEAR,
                            lock_random_generator::Bool = true,
                            num_actors::Int,
                            monetary_type::MonetaryType = M_FIXED,
                            allow_negative_accounts::Bool = true,
                            population_type::PopulationType = P_FIXED,
                            wealth_distribution::WealthDistribution = W_EQUAL,
                            gdp_scaling::Real = 1.0,
                            wealth_transfer::Real = 0.2,
                            wealth_accumulation_advantage::Real = 0,
                            taxes::Taxes,
                            tax_interval::Int = MONTH,
                            vat_active::Bool = false,
                            vat_interval::Int = MONTH,
                            percentage_tax_recipients::Real = 1,
                            distribute_real_expenditures::Bool = true) # Only applied when tax type is income tax or flat GDP tax.
    sim_params = SimParams(sim_length, lock_random_generator = lock_random_generator)

    if monetary_type == M_FIXED
        model = create_econo_model(MonetaryActor{Currency, Balance{Currency}})
        create_actor! = m -> create_monetary_actor!(m, allow_negative_assets = allow_negative_accounts)
    elseif monetary_type == M_SUMSY
        model = create_sumsy_model(sumsy_interval = get_sumsy_interval(country),
                                    model_behaviors = process_model_sumsy!)

        create_actor! = m -> create_sumsy_actor!(m,
                                                sumsy = SuMSy(get_flat_gi(country),
                                                                get_demurrage_free(country),
                                                                calculate_demurrage(country)),
                                                sumsy_interval = get_sumsy_interval(country),
                                                allow_negative_sumsy = allow_negative_accounts)
    elseif monetary_type == M_DEBT_BASED
        return # Not yet implemented
    end

    properties = abmproperties(model)
    properties[:country] = country
    properties[:accumulated_debt] = get_government_debt(country)

    if population_type == P_FIXED
        population_params = FixedPopulationParams(population = num_actors,
                                                    create_actor! = create_actor!)
    elseif population_type == P_DEMOGRAPHIC
        actor_types = Dict{Symbol, Real}()

        for age_group in instances(AgeGroup)
            actor_types[Symbol(age_group)] = get_percentage_population(country, age_group)
        end

        population_params = RelativeTypedPopulationParams(num_actors,
                                                            actor_types,
                                                            adjust_population_up(country),
                                                            adjust_population_down(country),
                                                            create_actor!)
            
    end

    transaction_params = GDPYardSaleParams(gdp_period = MONTH,
                                            gdp_per_capita = get_gdp_per_capita(country, period = MONTH) * gdp_scaling,
                                            wealth_transfer_range = wealth_transfer:wealth_transfer:wealth_transfer,
                                            minimal_wealth_transfer = 0,
                                            wealth_accumulation_advantage = wealth_accumulation_advantage,
                                            average_wealth = get_m_per_capita(country),
                                            adjust_income! = monetary_type == M_SUMSY ? m -> reset_gi!(m) : nothing)

    if wealth_distribution == W_EQUAL
        distribute_wealth! = m -> distribute_equal!(m, get_m_per_capita(country))
    elseif wealth_distribution == W_UNEQUAL
        if population_type == P_FIXED
            distribute_wealth! = m -> distribute_inequal!(m, get_wealth_inequality(country, WS_MONEY_STOCK))
        elseif population_type == P_DEMOGRAPHIC
            distribute_wealth! = m -> distribute_inequal!(m,
                                                            get_wealth_inequality(country, WS_MONEY_STOCK),
                                                            collect(keys(actor_types)))
        end
    end

    if monetary_type == M_FIXED
        monetary_params = FixedWealthParams(distribute_wealth! = distribute_wealth!)
    elseif monetary_type == M_SUMSY
        if population_type == P_FIXED
            configure_sumsy_actors! = m -> mixed_actors!(m)
        elseif population_type == P_DEMOGRAPHIC
            configure_sumsy_actors! = m -> type_based_sumsy_actors!(m,
                                                                    sumsy_groups = get_sumsy_groups(country),
                                                                    demurrage = calculate_demurrage(country, false))
        end

        monetary_params = StandardSuMSyParams(sumsy_interval = get_sumsy_interval(country),
                                                transactional = false,
                                                configure_sumsy_actors! = configure_sumsy_actors!,
                                                distribute_wealth! = distribute_wealth!)
    elseif monetary_type == M_DEBT_BASED
        return # Not yet implemented
    end

    init_income! = nothing

    if taxes == NO_TAX
        post_process_data! = post_process_no_tax_sim_data!
        tax_scheme = nothing
        adjust_distribution! = nothing
    else
        if taxes == T_INCOME_TAX || taxes == T_GDP_FLAT_TAX
            post_process_data! = post_process_sim_data!
            tax_type = INCOME_TAX
            tax_brackets = taxes == T_INCOME_TAX ? get_income_tax_brackets(country) : calculate_flat_gdp_tax(country)

            gdp_per_capita = get_gdp_per_capita(country, period = taxes == T_INCOME_TAX ? YEAR : MONTH)
            wealth_inequality = overlap_adjusted_inequality_data(get_wealth_inequality(country), num_actors)
            income_inequality = overlap_adjusted_inequality_data(get_income_inequality(country,
                                                                                        period = tax_interval,
                                                                                        scale = IS_GDP), num_actors)

            init_income! = a -> set_income!(a,
                                            wealth_distribution,
                                            gdp_per_capita,
                                            wealth_inequality,
                                            income_inequality)

            adjust_distribution! = distribute_real_expenditures ? adjust_tax_distribution! : nothing
        elseif taxes == T_DEM_TAX
            post_process_data! = a, m -> post_process_sim_data!(a, m, true)
            tax_type = DEMURRAGE_TAX
            tax_brackets = calculate_dem_tax(country)
            adjust_distribution! = nothing
        elseif taxes == T_VAT_ONLY
            post_process_data! = post_process_sim_data!
            tax_type = VAT_ONLY
            tax_brackets = 0
            adjust_distribution! = nothing
        end

        if vat_active
            vat = calculate_avg_vat(country)
        else
            vat = 0
        end

        tax_scheme = FixedTaxScheme(tax_type,
                                    tax_recipients = round(num_actors * percentage_tax_recipients),
                                    tax_calculation_interval = tax_interval,
                                    tax_redistribution_interval = MONTH,
                                    tax_brackets = tax_brackets,
                                    tax_free = 0,
                                    vat_interval = vat_interval,
                                    vat = vat,
                                    initial_income! = init_income!,
                                    distribution_adjustment! = adjust_distribution!)
    end

    actor_data_handlers = [deposit_collector,
                            equity_collector,
                            income_collector!,
                            expenses_collector!,
                            paid_tax_collector!,
                            paid_vat_collector!,
                            tax_share_collector!,
                            vat_share_collector!]

    if monetary_type == M_SUMSY
        push!(actor_data_handlers, gi_collector!)
        push!(actor_data_handlers, dem_collector!)
    end

    if population_type == P_DEMOGRAPHIC
        push!(actor_data_handlers, :types)
    end

    model_data_collectors = [nagents,
                            gdp_collector!,
                            transactions_collector!,
                            min_transaction_collector!,
                            max_transaction_collector!,
                            tax_collector!,
                            failed_tax_collector!,
                            vat_collector!,
                            failed_vat_collector!,
                            accumulated_debt_collector]

    if monetary_type == M_SUMSY
        push!(model_data_collectors, total_gi_collector!)
        push!(model_data_collectors, total_demurrage_collector!)
    end

    data_handler = IntervalDataHandler(interval = data_collection_interval,
                                        actor_data_collectors = actor_data_handlers,
                                        model_data_collectors = model_data_collectors,
                                        post_processing! = post_process_data!)

    run_simulation(model,
                    sim_params = sim_params,
                    population_params = population_params,
                    monetary_params = monetary_params,
                    transaction_params = transaction_params,
                    tax_scheme = tax_scheme,
                    data_handler = data_handler)
end