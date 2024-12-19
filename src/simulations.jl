using EconoSim
using Agents
using Random
using DataFrames

"""
    struct SimParams
        * sim_length::Int - The number of iterations of the simulation.
        * lock_random_generator::Bool - Lock the random number generator to a fixed seed, thereby producing reproducible results.

    General simulation parameters.
"""
struct SimParams
    sim_length::Int
    lock_random_generator::Bool
    SimParams(sim_length::Int;
              lock_random_generator::Bool = true) = new(sim_length, lock_random_generator)
end

# General simulation

function run_simulation(model::ABM;
                        sim_params::SimParams,
                        population_params::PopulationParams = FixedPopulationParams(1000),
                        behaviour_params::Union{BehaviourParams, Nothing} = nothing,
                        monetary_params::MonetaryModelParams,
                        tax_scheme::Union{Nothing, TaxScheme} = nothing,
                        data_handler::Union{DataHandler, Nothing} = nothing,
                        termination_handler::Union{TerminationHandler, Nothing} = nothing,
                        initialisations::Vector{<: Function} = Vector{Function}(),
                        model_adaptations::Vector{<: Function} = Vector{Function}(),
                        collect_initial_data::Bool = true)
    set_random_seed!(sim_params.lock_random_generator)

    properties = abmproperties(model)
    properties[:last_transaction] = model.step
    properties[:termination_flag] = false

    initialize_population_model!(model, population_params)

    if !isnothing(behaviour_params)
        initialize_behaviour_model!(model, behaviour_params)
    end
    
    initialize_monetary_model!(model, monetary_params)

    if !isnothing(tax_scheme)
        initialize_tax_scheme!(model, tax_scheme)
    end

    if !isnothing(data_handler)
        when, a_collectors, m_collectors = initialize_data_handler!(model, data_handler)
    else
        when = false
        a_collectors = []
        m_collectors = []
    end

    if !isnothing(termination_handler)
        initialize_termination_handler!(model, termination_handler)
    end

    for initialisation in initialisations
        initialisation(model)
    end

    for model_adaptation in model_adaptations
        add_model_behavior!(model, model_adaptation)
    end

    actor_data, model_data = run_econo_model!(model,
                                            sim_params.sim_length,
                                            adata = a_collectors,
                                            mdata = m_collectors,
                                            when = when,
                                            init = collect_initial_data)

    return post_process!(data_handler, actor_data, model_data)
end

# Fixed wealth simulation

function run_fixed_wealth_simulation(fixed_wealth_params::FixedWealthParams;
                                    sim_params::SimParams,
                                    population_params::PopulationParams = FixedPopulationParams(1000),
                                    behaviour_params::Union{BehaviourParams, Nothing} = nothing,
                                    tax_scheme::Union{Nothing, TaxScheme} = nothing,
                                    data_handler::Union{DataHandler, Nothing} = nothing,
                                    termination_handler::Union{TerminationHandler, Nothing} = nothing,
                                    initialisations::Vector{<: Function} = Vector{Function}(),
                                    model_adaptations::Vector{<: Function} = Vector{Function}(),
                                    collect_initial_data::Bool = true)
    model = create_econo_model()

    run_simulation(model,
                    sim_params = sim_params,
                    population_params = population_params,
                    behaviour_params = behaviour_params,
                    monetary_params = fixed_wealth_params,
                    tax_scheme = tax_scheme,
                    data_handler = data_handler,
                    termination_handler = termination_handler,
                    initialisations = initialisations,
                    model_adaptations = model_adaptations,
                    collect_initial_data = collect_initial_data)
end

function run_fixed_wealth_simulation(;
                                    num_actors::Int = 1000,
                                    num_transactions::Int = 200,
                                    initial_wealth::Real = 200000,
                                    remove_broke_actors::Bool = true,
                                    sim_length::Int = 150,
                                    period::Int = 30,
                                    population_params::PopulationParams = FixedPopulationParams(num_actors),
                                    tax_scheme::Union{Nothing, TaxScheme} = nothing,
                                    data_handler::DataHandler = full_data_handler(period),
                                    termination_handler::Union{TerminationHandler, Nothing} = nothing,
                                    initialisations::Vector{<: Function} = Vector{Function}(),
                                    model_adaptations::Vector{<: Function} = Vector{Function}(),
                                    collect_initial_data::Bool = true)
    sim_params = SimParams(sim_length * period)
    fixed_wealth_params = FixedWealthParams(initial_wealth, true)
    yard_sale_params = StandardYardSaleParams(num_transactions:num_transactions,
                                                0.2:0.2:0.2,
                                                0,
                                                remove_broke_actors)

    run_fixed_wealth_simulation(fixed_wealth_params,
                                sim_params = sim_params,
                                population_params = population_params,
                                behaviour_params = yard_sale_params,
                                tax_scheme = tax_scheme,
                                data_handler = data_handler,
                                termination_handler = termination_handler,
                                initialisations = initialisations,
                                model_adaptations = model_adaptations,
                                collect_initial_data = collect_initial_data)
end

function run_fixed_wealth_gdp_simulation(;
                                        num_actors::Int,
                                        initial_wealth::Real = 200000,
                                        remove_broke_actors::Bool = true,
                                        wealth_transfer::Real = 0.2,
                                        gdp_per_capita::Real,
                                        years::Int,
                                        tax_scheme::Union{Nothing, TaxScheme} = nothing,
                                        population_params::PopulationParams = FixedPopulationParams(num_actors),
                                        data_handler::DataHandler = gdp_data_handler(),
                                        termination_handler::Union{TerminationHandler, Nothing} = nothing,
                                        initialisations::Vector{<: Function} = Vector{Function}(),
                                        model_adaptations::Vector{<: Function} = Vector{Function}())
    sim_params = SimParams(years)
    fixed_wealth_params = FixedWealthParams(initial_wealth, true)
    yard_sale_params = GDPYardSaleParams(1, # Period length is set to 1 year
                                        gdp_per_capita,
                                        wealth_transfer:wealth_transfer:wealth_transfer,
                                        0,
                                        remove_broke_actors,
                                        gdp_yard_sale!)

    run_fixed_wealth_simulation(fixed_wealth_params,
                                population_params = population_params,
                                sim_params = sim_params,
                                behaviour_params = yard_sale_params,
                                tax_scheme = tax_scheme,
                                data_handler = data_handler,
                                termination_handler = termination_handler,
                                initialisations = initialisations,
                                model_adaptations = model_adaptations)
end

# SuMSy simulation

function run_sumsy_simulation(sumsy::SuMSy,
                                sumsy_params::SuMSyParams;
                                sim_params::SimParams,
                                population_params::PopulationParams = FixedPopulationParams(1000, create_sumsy_actor),
                                behaviour_params::Union{BehaviourParams, Nothing} = nothing,
                                tax_scheme::Union{Nothing, TaxScheme} = nothing,
                                data_handler::Union{DataHandler, Nothing} = nothing,
                                termination_handler::Union{TerminationHandler, Nothing} = nothing,
                                initialisations::Vector{<: Function} = Vector{Function}(),
                                model_adaptations::Vector{<: Function} = Vector{Function}())
    if sumsy.transactional
        model = create_sumsy_model(sumsy)
    else
        model = create_sumsy_model(sumsy, model_behaviors = process_model_sumsy!)
    end
    
    run_simulation(model,
                    sim_params = sim_params,
                    behaviour_params = behaviour_params,
                    monetary_params = sumsy_params,
                    tax_scheme = tax_scheme,
                    population_params = population_params,
                    data_handler = data_handler,
                    termination_handler = termination_handler,
                    initialisations = initialisations,
                    model_adaptations = model_adaptations)
end

function run_sumsy_simulation(sumsy::SuMSy;
                                eligible_actors::Int = 1000,
                                non_eligible_actors::Int = 0,
                                num_transactions::Int = 200,
                                period_length::Int = sumsy.interval,
                                sim_length::Int = 150,
                                distributed::Bool = true,
                                tax_scheme::Union{Nothing, TaxScheme} = nothing,
                                population_params::PopulationParams = FixedPopulationParams(eligible_actors + non_eligible_actors,
                                                                                            create_sumsy_actor),
                                data_handler::DataHandler = money_stock_data_handler(period_length),
                                termination_handler::Union{TerminationHandler, Nothing} = nothing,
                                initialisations::Vector{<: Function} = Vector{Function}(),
                                model_adaptation::Union{Function, Nothing} = nothing)
    sim_params = SimParams(sim_length * period_length)

    initial_wealth = telo(sumsy)

    if non_eligible_actors > 0
        configure_sumsy_actors! = model -> mixed_actors!(model, eligible_actors)
    else
        configure_sumsy_actors! = mixed_actors!
    end

    if non_eligible_actors > 0
        initial_wealth *= eligible_actors / (eligible_actors + non_eligible_actors)
    end


    sumsy_params = StandardSuMSyParams(initial_wealth,
                                        initial_wealth,
                                        configure_sumsy_actors! = configure_sumsy_actors!,
                                        distribute_wealth! = distributed ? equal_wealth_distribution! : concentrated_wealth_distribution!)
    behaviour_params = StandardYardSaleParams(num_transactions:num_transactions,
                                                0.2:0.2:0.2,
                                                0,
                                                false)
    model_adaptations = isnothing(model_adaptation) ? Vector{Function}() : Vector{Function}([model_adaptation])

    run_sumsy_simulation(sumsy,
                            sumsy_params,
                            sim_params = sim_params,
                            population_params = population_params,
                            behaviour_params = behaviour_params,
                            tax_scheme = tax_scheme,
                            data_handler = data_handler,
                            termination_handler = termination_handler,
                            initialisations = initialisations,
                            model_adaptations = model_adaptations)
end

function run_sumsy_gdp_simulation(sumsy::SuMSy;
                                    eligible_actors::Int = 1000,
                                    non_eligible_actors::Int = 0,
                                    initial_wealth::Real = telo(sumsy),
                                    wealth_transfer::Real = 0.2,
                                    gdp_per_capita::Real,
                                    years::Int,
                                    tax_scheme::Union{Nothing, TaxScheme} = nothing,
                                    population_params::PopulationParams = FixedPopulationParams(eligible_actors + non_eligible_actors,
                                                                                                create_sumsy_actor),
                                    data_handler::DataHandler = gdp_data_handler(12 * sumsy.interval),
                                    termination_handler::Union{TerminationHandler, Nothing} = nothing,
                                    initialisations::Vector{<: Function} = Vector{Function}(),
                                    model_adaptations::Vector{<: Function} = Vector{Function}())
    period = 12 * sumsy.interval
    sim_params = SimParams(years * period)

    if non_eligible_actors > 0
        configure_sumsy_actors! = model -> mixed_actors!(model, eligible_actors)
    else
        configure_sumsy_actors! = mixed_actors!
    end

    if non_eligible_actors > 0
        initial_wealth *= eligible_actors / (eligible_actors + non_eligible_actors)
    end


    sumsy_params = StandardSuMSyParams(initial_wealth,
                                        initial_wealth,
                                        configure_sumsy_actors! = configure_sumsy_actors!)
    yard_sale_params = GDPYardSaleParams(period,
                                        gdp_per_capita,
                                        wealth_transfer:wealth_transfer:wealth_transfer,
                                        0,
                                        false,
                                        gdp_yard_sale!)


    run_sumsy_simulation(sumsy,
                        sumsy_params,
                        sim_params = sim_params,
                        population_params = population_params,
                        behaviour_params = yard_sale_params,
                        tax_scheme = tax_scheme,
                        data_handler = data_handler,
                        termination_handler = termination_handler,
                        initialisations = initialisations,
                        model_adaptations = model_adaptations)
end

function run_consumer_supplier_simulation(sumsy::SuMSy;
                                            sim_length::Int = 150,
                                            consumers_per_supplier::Int = 100,
                                            fulfilled_demand::Int = 1,
                                            net_profit::Real = 1,
                                            suppliers_gi_eligible = false,
                                            tax_scheme::Union{Nothing, TaxScheme} = nothing,
                                            population_params = FixedPopulationParams(0, create_sumsy_actor),
                                            data_handler::DataHandler = full_data_handler(sumsy.interval),
                                            termination_handler::Union{TerminationHandler, Nothing} = nothing,
                                            initialisations::Vector{<: Function} = Vector{Function}(),
                                            model_adaptations::Vector{<: Function} = Vector{Function}())
    sim_params = SimParams(sim_length * sumsy.interval)

    gi_eligible_types = suppliers_gi_eligible ? [:supplier, :consumer] : [:consumer]
    sumsy_params = StandardSuMSyParams(telo(sumsy), configure_sumsy_actors! = model -> typed_gi_actors!(model, gi_eligible_types))
    consumer_supply_params = FixedConsumerSupplyParams(1, consumers_per_supplier, fulfilled_demand, net_profit)

    return run_sumsy_simulation(sumsy,
                                sumsy_params,
                                sim_params = sim_params,
                                population_params = population_params,
                                behaviour_params = consumer_supply_params,
                                tax_scheme = tax_scheme,
                                data_handler = data_handler,
                                termination_handler = termination_handler,
                                initialisations = initialisations,
                                model_adaptations = model_adaptations)
end

function run_debt_based_simulation(debt_based_params::DebtBasedParams;
                                    sim_params::SimParams,
                                    behaviour_params::Union{BehaviourParams, Nothing} = nothing,
                                    tax_scheme::Union{Nothing, TaxScheme} = nothing,
                                    population_params::PopulationParams = FixedPopulationParams(1000),
                                    data_handler::Union{DataHandler, Nothing} = nothing,
                                    termination_handler::Union{TerminationHandler, Nothing} = nothing,
                                    initialisations::Vector{<: Function} = Vector{Function}(),
                                    model_adaptations::Vector{<: Function} = Vector{Function}())
    model = create_econo_model()

    run_simulation(model,
                    sim_params = sim_params,
                    population_params = population_params,
                    behaviour_params = behaviour_params, 
                    monetary_params = debt_based_params,
                    tax_scheme = tax_scheme,
                    data_handler = data_handler,
                    termination_handler = termination_handler,
                    initialisations = initialisations,
                    model_adaptations = model_adaptations)
end

# Utility functions

function set_random_seed!(lock_random_generator::Bool)
    if lock_random_generator
        Random.seed!(35646516187576568)
    else
        Random.seed(Integer(round(time())))
    end
end