using EconoSim
using MoneySim
using DataFrames
using Agents
using Intervals

@enum PopulationType P_FIXED P_DEMOGRAPHIC
@enum MonetaryType M_FIXED M_SUMSY M_GI_ONLY M_DEBT_BASED
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
            7 => :taxed_amount,
            8 => :paid_tax,
            9 => :net_income,
            10 => :paid_vat,
            11 => :tax_share,
            12 => :vat_share)

    rename!(model_data,
            2 => :num_actors,
            3 => :gdp,
            4 => :transactions,
            5 => :min_transaction,
            6 => :max_transaction,
            7 => :projected_expenses,
            8 => :projected_revenue,
            9 => :collected_tax,
            10 => :tax_scale,
            11 => :tax_brackets,
            12 => :failed_tax,
            13 => :collected_vat,
            14 => :failed_vat,
            15 => :debt)

    if sumsy_sim
        rename!(actor_data,
                13 => :gi,
                14 => :demurrage
        )
        rename!(model_data,
                16 => :total_gi,
                17 => :total_demurrage)
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
        else
            throw("No matching wealth found: $wealth")
        end
    end

    actor.data_income = actor.income
end

function calculate_sumsy_expenses(country::Country, tax_interval::Int)
    return get_net_expenses_per_capita(country, period = tax_interval)
            + get_pension_cost_per_capita(country, period = tax_interval)
            - get_percentage_population(country, POP_65_PLUS) * get_flat_gi(country) # pension cost covered ny GI
            - get_unemployment_cost_per_capita(country, period = tax_interval)
end

function average_wealth(model::ABM)
    total_wealth = CUR_0
    
    for actor in allagents(model)
        total_wealth += asset_value(get_balance(actor), SUMSY_DEP)
    end

    return Currency(total_wealth / nagents(model))
end

function gdp_growth(model::ABM, period::Int, gdp_growth_per_year::Real)
    return gdp_growth_per_year / 12 * period
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
                            gdp_growth_per_year::Real = 0,
                            wealth_transfer::Real = 0.2,
                            wealth_accumulation_advantage::Real = 0,
                            taxes::Taxes,
                            reduced_expenses::Bool = false,
                            deficit_spending::Bool = true,
                            cover_expenses::Bool = taxes == T_DEM_TAX,
                            scale_tax_to_target_revenue = false,
                            tax_interval::Int = MONTH,
                            vat_active::Bool = false,
                            deduct_vat_from_taxes::Bool = false,
                            vat_interval::Int = MONTH,
                            percentage_tax_recipients::Real = 1,
                            interest_rate_on_debt::Real = get_interest_cost_per_capita(country) / get_government_debt_per_capita(country))
    # Simulation parameters
    sim_params = SimParams(sim_length, lock_random_generator = lock_random_generator)

    # Model
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

    # Country data
    properties = abmproperties(model)
    properties[:country] = country

    # Population model
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

    # Transaction model
    transaction_params = GDPYardSaleParams(gdp_period = MONTH,
                                            gdp_per_capita = get_gdp_per_capita(country, period = MONTH) * gdp_scaling,
                                            gdp_growth = (m, p) -> gdp_growth(m, p, gdp_growth_per_year),
                                            wealth_transfer_range = wealth_transfer:wealth_transfer:wealth_transfer,
                                            minimal_wealth_transfer = 0,
                                            wealth_accumulation_advantage = wealth_accumulation_advantage,
                                            average_wealth = average_wealth)

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

    # Monetary system
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


    gdp_per_capita = get_gdp_per_capita(country, period = tax_interval)
    wealth_inequality = overlap_adjusted_inequality_data(get_wealth_inequality(country), num_actors)
    income_inequality = overlap_adjusted_inequality_data(get_income_inequality(country,
                                                                                period = tax_interval,
                                                                                scale = IS_GDP), num_actors)

    init_income! = a -> set_income!(a,
                                    wealth_distribution,
                                    gdp_per_capita,
                                    wealth_inequality,
                                    income_inequality)

    # Taxation model
    adjust_taxes! = nothing
    
    if taxes == T_INCOME_TAX || taxes == T_GDP_FLAT_TAX
        post_process_data! = post_process_sim_data!
        tax_type = INCOME_TAX

        if taxes == T_INCOME_TAX
            tax_brackets = get_income_tax_brackets(country)
        else # taxes == T_GDP_FLAT_TAX
            tax_brackets = calculate_flat_gdp_income_tax(country, period = tax_interval)
        end

        projected_expenses_per_capita = cover_expenses || deficit_spending ?
                                        p -> get_net_expenses_per_capita(country, period = p) :
                                        p -> get_income_per_capita(country, period = p)
    elseif taxes == T_DEM_TAX
        post_process_data! = (a, m) -> post_process_sim_data!(a, m, true)
        tax_type = DEMURRAGE_TAX

        projected_expenses_per_capita = reduced_expenses ?
                                            p -> calculate_sumsy_expenses(country, p) :
                                            p -> get_net_expenses_per_capita(country, period = p)
        tax_brackets = calculate_dem_tax(country, period = tax_interval, expenses_per_capita = projected_expenses_per_capita(tax_interval))
    elseif taxes == T_VAT_ONLY
        post_process_data! = post_process_sim_data!
        tax_type = VAT_ONLY
        tax_brackets = 0
        projected_expenses_per_capita = p -> 0
    elseif taxes == T_NO_TAX
        post_process_data! = post_process_sim_data!
        tax_type = NO_TAX
        tax_brackets = 0
    end

    if vat_active
        avg_vat = calculate_avg_vat(country)
    else
        avg_vat = 0
    end

    vat = (_, _) -> avg_vat

    if cover_expenses
        target_revenue = (_, p) -> get_net_expenses_per_capita(country, period = p) * num_actors
    else
        target_revenue = (_, p) -> get_income_per_capita(country, period = p) * num_actors
    end

    get_tax_brackets = (_, _) -> tax_brackets

    tax_scheme = StateTaxScheme(tax_type,
                                tax_recipients = round(num_actors * percentage_tax_recipients),
                                tax_calculation_interval = tax_interval,
                                tax_redistribution_interval = MONTH,
                                initial_income! = init_income!,
                                get_tax_brackets = get_tax_brackets,
                                scale_tax_to_target_revenue = scale_tax_to_target_revenue,
                                get_target_revenue = target_revenue,
                                vat_interval = vat_interval,
                                get_vat = vat,
                                deduct_vat_from_taxes = deduct_vat_from_taxes,
                                get_projected_expenses = (_, p) -> projected_expenses_per_capita(p) * num_actors,
                                deficit_spending = deficit_spending,
                                initial_debt = get_government_debt_per_capita(country) * num_actors,
                                debt_reduction = m -> 0)

    # Data handlers
    actor_data_collectors = [deposit_collector,
                            equity_collector,
                            income_collector!,
                            expenses_collector!,
                            taxed_amount_collector!,
                            paid_tax_collector!,
                            net_income_collector!,
                            paid_vat_collector!,
                            tax_share_collector!,
                            vat_share_collector!]

    if monetary_type == M_SUMSY
        push!(actor_data_collectors, gi_collector!)
        push!(actor_data_collectors, demurrage_collector!)
    end

    if population_type == P_DEMOGRAPHIC
        push!(actor_data_handlers, :types)
    end

    model_data_collectors = [nagents,
                            gdp_collector!,
                            transactions_collector!,
                            min_transaction_collector!,
                            max_transaction_collector!,
                            projected_expenses_collector!,
                            projected_revenue_collector!,
                            tax_collector!,
                            tax_scale_collector!,
                            tax_brackets_collector!,
                            failed_tax_collector!,
                            vat_collector!,
                            failed_vat_collector!,
                            debt_collector]

    if monetary_type == M_SUMSY
        push!(model_data_collectors, total_gi_collector!)
        push!(model_data_collectors, total_demurrage_collector!)
    end

    data_handler = IntervalDataHandler(interval = data_collection_interval,
                                        actor_data_collectors = actor_data_collectors,
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