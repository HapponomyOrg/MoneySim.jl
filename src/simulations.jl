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

function initialize_simulation!(model::ABM;
                                sim_params::SimParams,
                                population_params::PopulationParams = FixedPopulationParams(population = 1000),
                                monetary_params::MonetaryModelParams,
                                transaction_params::Union{TransactionParams, Nothing} = nothing,
                                tax_scheme::Union{Nothing, TaxScheme} = nothing,
                                data_handler::Union{DataHandler, Nothing} = nothing,
                                termination_handler::Union{TerminationHandler, Nothing} = nothing,
                                model_initialisations::Vector{<: Function} = Vector{Function}(),
                                actor_initialisations::Vector{<: Function} = Vector{Function}(),
                                model_adaptations::Vector{<: Function} = Vector{Function}())
    set_random_seed!(sim_params.lock_random_generator)

    properties = abmproperties(model)
    properties[:last_transaction] = 0
    properties[:termination_flag] = false

    initialize_population_model!(model, population_params)
    
    initialize_monetary_model!(model, monetary_params)

    if !isnothing(transaction_params)
        initialize_transaction_model!(model, transaction_params)
    end

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

    for initialisation in model_initialisations
        initialisation(model)
    end

    for initialisation in actor_initialisations
        for actor in allagents(model)
            initialisation(actor)
        end
    end

    for model_adaptation in model_adaptations
        add_model_behavior!(model, model_adaptation)
    end

    if !isnothing(termination_handler)
        initialize_termination_handler!(model, termination_handler)
    end

    return when, a_collectors, m_collectors
end

"""
    run_simulation(model::ABM;
                    sim_params::SimParams,
                    population_params::PopulationParams = FixedPopulationParams(population = 1000),
                    monetary_params::MonetaryModelParams,
                    transaction_params::Union{TransactionParams, Nothing} = nothing,
                    tax_scheme::Union{Nothing, TaxScheme} = nothing,
                    data_handler::Union{DataHandler, Nothing} = nothing,
                    termination_handler::Union{TerminationHandler, Nothing} = nothing,
                    model_initialisations::Vector{<: Function} = Vector{Function}(),
                    actor_initialisations::Vector{<: Function} = Vector{Function}(),
                    model_adaptations::Vector{<: Function} = Vector{Function}(),
                    collect_initial_data::Bool = true)

    * model::ABM : 
    sim_params::SimParams : 
    population_params::PopulationParams : 
    monetary_params::MonetaryModelParams : 
    transaction_params::Union{TransactionParams, Nothing} : 
    tax_scheme::Union{Nothing, TaxScheme} : 
    data_handler::Union{DataHandler, Nothing} : 
    termination_handler::Union{TerminationHandler, Nothing} : 
    model_initialisations::Vector{<: Function} : 
    actor_initialisations::Vector{<: Function} : 
    model_adaptations::Vector{<: Function} : 
    collect_initial_data::Bool : 

    Run the simulation based on the configuration parameters.
    If every module adds model behavior after the other modules, the simulation does the following in order:
    - Model level activity:
        - Population evolvement.
        - Monetary policy.
        - Execution of the transaction model.
        - Taxation and redistribution.
        - Additional model behaviour.
        - Check for termination.
    
    Individual actor activation should be handled in the appropriate modules. No default actor activation is executed.
"""
function run_simulation(model::ABM;
                        sim_params::SimParams,
                        population_params::PopulationParams = FixedPopulationParams(population = 1000),
                        monetary_params::MonetaryModelParams,
                        transaction_params::Union{TransactionParams, Nothing} = nothing,
                        tax_scheme::Union{Nothing, TaxScheme} = nothing,
                        data_handler::Union{DataHandler, Nothing} = nothing,
                        termination_handler::Union{TerminationHandler, Nothing} = nothing,
                        model_initialisations::Vector{<: Function} = Vector{Function}(),
                        actor_initialisations::Vector{<: Function} = Vector{Function}(),
                        model_adaptations::Vector{<: Function} = Vector{Function}(),
                        collect_initial_data::Bool = true)
    when, a_collectors, m_collectors = initialize_simulation!(model,
                                                                sim_params = sim_params,
                                                                population_params = population_params,
                                                                monetary_params = monetary_params,
                                                                transaction_params = transaction_params,
                                                                tax_scheme = tax_scheme,
                                                                data_handler = data_handler,
                                                                termination_handler = termination_handler,
                                                                model_initialisations = model_initialisations,
                                                                actor_initialisations = actor_initialisations,
                                                                model_adaptations = model_adaptations)
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
                                    population_params::PopulationParams = FixedPopulationParams(population = 1000),
                                    transaction_params::Union{TransactionParams, Nothing} = nothing,
                                    tax_scheme::Union{Nothing, TaxScheme} = nothing,
                                    data_handler::Union{DataHandler, Nothing} = nothing,
                                    termination_handler::Union{TerminationHandler, Nothing} = nothing,
                                    model_initialisations::Vector{<: Function} = Vector{Function}(),
                                    actor_initialisations::Vector{<: Function} = Vector{Function}(),
                                    model_adaptations::Vector{<: Function} = Vector{Function}(),
                                    collect_initial_data::Bool = true)
    model = create_econo_model()

    run_simulation(model,
                    sim_params = sim_params,
                    population_params = population_params,
                    monetary_params = fixed_wealth_params,
                    transaction_params = transaction_params,
                    tax_scheme = tax_scheme,
                    data_handler = data_handler,
                    termination_handler = termination_handler,
                    model_initialisations = model_initialisations,
                    actor_initialisations = actor_initialisations,
                    model_adaptations = model_adaptations,
                    collect_initial_data = collect_initial_data)
end

function run_fixed_wealth_simulation(;
                                    num_actors::Int = 1000,
                                    num_transactions::Int = 200,
                                    initial_wealth::Real = 200000,
                                    wealth_transfer::Union{StepRange, StepRangeLen} = 0.2:0.2:0.2,
                                    min_wealth_transfer::Real = 0,
                                    waa::Real = 0,
                                    sim_length::Int = 150,
                                    period::Int = 30,
                                    population_params::PopulationParams = FixedPopulationParams(population = num_actors),
                                    tax_scheme::Union{Nothing, TaxScheme} = nothing,
                                    data_handler::DataHandler = full_data_handler(period),
                                    termination_handler::Union{TerminationHandler, Nothing} = nothing,
                                    model_initialisations::Vector{<: Function} = Vector{Function}(),
                                    actor_initialisations::Vector{<: Function} = Vector{Function}(),
                                    model_adaptations::Vector{<: Function} = Vector{Function}(),
                                    collect_initial_data::Bool = true)
    sim_params = SimParams(sim_length * period)
    fixed_wealth_params = FixedWealthParams(x -> distribute_equal!(x, initial_wealth))
    yard_sale_params = StandardYardSaleParams(transaction_range = num_transactions:num_transactions,
                                                wealth_transfer_range = wealth_transfer,
                                                minimal_wealth_transfer = min_wealth_transfer,
                                                wealth_advantage_adjustment = waa,
                                                average_wealth = initial_wealth)

    run_fixed_wealth_simulation(fixed_wealth_params,
                                sim_params = sim_params,
                                population_params = population_params,
                                transaction_params = yard_sale_params,
                                tax_scheme = tax_scheme,
                                data_handler = data_handler,
                                termination_handler = termination_handler,
                                model_initialisations = model_initialisations,
                                actor_initialisations = actor_initialisations,
                                model_adaptations = model_adaptations,
                                collect_initial_data = collect_initial_data)
end

function run_fixed_wealth_gdp_simulation(;
                                        num_actors::Int,
                                        initial_wealth::Real = 200000,
                                        wealth_transfer::Real = 0.2,
                                        min_wealth_transfer::Real = 0,
                                        waa::Real = 0,
                                        gdp_per_capita::Real,
                                        years::Int,
                                        population_params::PopulationParams = FixedPopulationParams(population = num_actors),
                                        tax_scheme::Union{Nothing, TaxScheme} = nothing,
                                        data_handler::DataHandler = isnothing(tax_scheme) ? raw_gdp_data_handler() : gdp_data_handler(),
                                        termination_handler::Union{TerminationHandler, Nothing} = nothing,
                                        model_initialisations::Vector{<: Function} = Vector{Function}(),
                                        actor_initialisations::Vector{<: Function} = Vector{Function}(),
                                        model_adaptations::Vector{<: Function} = Vector{Function}())
    sim_params = SimParams(years)
    fixed_wealth_params = FixedWealthParams(x -> distribute_equal!(x, initial_wealth))
    yard_sale_params = GDPYardSaleParams(gdp_period = 1, # Period length is set to 1 year
                                        gdp_per_capita = gdp_per_capita,
                                        wealth_transfer_range = wealth_transfer:wealth_transfer:wealth_transfer,
                                        minimal_wealth_transfer = min_wealth_transfer,
                                        adjust_income! = nothing,
                                        wealth_advantage_adjustment = waa,
                                        average_wealth = initial_wealth)

    run_fixed_wealth_simulation(fixed_wealth_params,
                                population_params = population_params,
                                sim_params = sim_params,
                                transaction_params = yard_sale_params,
                                tax_scheme = tax_scheme,
                                data_handler = data_handler,
                                termination_handler = termination_handler,
                                model_initialisations = model_initialisations,
                                actor_initialisations = actor_initialisations,
                                model_adaptations = model_adaptations)
end

# SuMSy simulation

function run_sumsy_simulation(sumsy_params::SuMSyParams;
                                sim_params::SimParams,
                                population_params::PopulationParams = FixedPopulationParams(population = 1000,
                                                                                            create_actor! = m -> create_sumsy_actor!(m,
                                                                                                                                    sumsy = sumsy,
                                                                                                                                    sumsy_interval = sumsy_interval,
                                                                                                                                    transactional = sumsy_params.transactional)),
                                transaction_params::Union{TransactionParams, Nothing} = nothing,
                                tax_scheme::Union{Nothing, TaxScheme} = nothing,
                                data_handler::Union{DataHandler, Nothing} = nothing,
                                termination_handler::Union{TerminationHandler, Nothing} = nothing,
                                model_initialisations::Vector{<: Function} = Vector{Function}(),
                                actor_initialisations::Vector{<: Function} = Vector{Function}(),
                                model_adaptations::Vector{<: Function} = Vector{Function}())
    if sumsy_params.transactional
        model = create_sumsy_model(sumsy_interval = sumsy_params.sumsy_interval)
    else
        model = create_sumsy_model(sumsy_interval = sumsy_params.sumsy_interval, model_behaviors = process_model_sumsy!)
    end
    
    run_simulation(model,
                    sim_params = sim_params,
                    population_params = population_params,
                    monetary_params = sumsy_params,
                    transaction_params = transaction_params,
                    tax_scheme = tax_scheme,
                    data_handler = data_handler,
                    termination_handler = termination_handler,
                    model_initialisations = model_initialisations,
                    actor_initialisations = actor_initialisations,
                    model_adaptations = model_adaptations)
end

function run_sumsy_simulation(sumsy::SuMSy;
                                sumsy_interval::Int = 30,
                                sumsy_transactional::Bool = false,
                                eligible_actors::Int = 1000,
                                non_eligible_actors::Int = 0,
                                num_transactions::Int = 200,
                                period_length::Int = sumsy_interval,
                                sim_length::Int = 150,
                                distributed::Bool = true,
                                wealth_transfer::Real = 0.2,
                                min_wealth_transfer::Real = 0,
                                waa::Real = 0,
                                population_params::PopulationParams = FixedPopulationParams(population = eligible_actors + non_eligible_actors,
                                                                                            create_actor! = m -> create_sumsy_actor!(m,
                                                                                                                                    sumsy = sumsy,
                                                                                                                                    sumsy_interval = sumsy_interval,
                                                                                                                                    transactional = sumsy_transactional)),
                                tax_scheme::Union{Nothing, TaxScheme} = nothing,
                                data_handler::DataHandler = money_stock_data_handler(period_length),
                                termination_handler::Union{TerminationHandler, Nothing} = nothing,
                                model_initialisations::Vector{<: Function} = Vector{Function}(),
                                actor_initialisations::Vector{<: Function} = Vector{Function}(),
                                model_adaptation::Union{Function, Nothing} = nothing)
    sim_params = SimParams(sim_length * period_length)

    initial_wealth = telo(sumsy)

    if non_eligible_actors > 0
        configure_sumsy_actors! = model -> mixed_actors!(model, num_gi_actors = eligible_actors)
    else
        configure_sumsy_actors! = mixed_actors!
    end

    if non_eligible_actors > 0
        initial_wealth *= eligible_actors / (eligible_actors + non_eligible_actors)
    end


    sumsy_params = create_StandardSuMSyParams(sumsy_interval = sumsy_interval,
                                                transactional = sumsy_transactional,
                                                configure_sumsy_actors! = configure_sumsy_actors!,
                                                initial_gi_wealth = initial_wealth,
                                                initial_non_gi_wealth = initial_wealth,
                                                distribute = distributed)
    transaction_params = StandardYardSaleParams(transaction_range = num_transactions:num_transactions,
                                                wealth_transfer_range = wealth_transfer:wealth_transfer:wealth_transfer,
                                                minimal_wealth_transfer = min_wealth_transfer,
                                                wealth_accumulation_advantage = waa,
                                                average_wealth = initial_wealth)
    model_adaptations = isnothing(model_adaptation) ? Vector{Function}() : Vector{Function}([model_adaptation])

    run_sumsy_simulation(sumsy_params,
                            sim_params = sim_params,
                            population_params = population_params,
                            transaction_params = transaction_params,
                            tax_scheme = tax_scheme,
                            data_handler = data_handler,
                            termination_handler = termination_handler,
                            model_initialisations = model_initialisations,
                            actor_initialisations = actor_initialisations,
                            model_adaptations = model_adaptations)
end

function run_sumsy_gdp_simulation(sumsy::SuMSy;
                                    sumsy_interval::Int = 30,
                                    sumsy_transactional::Bool = false,
                                    eligible_actors::Int = 1000,
                                    non_eligible_actors::Int = 0,
                                    initial_wealth::Real = telo(sumsy),
                                    wealth_transfer::Real = 0.2,
                                    waa = 0,
                                    gdp_per_capita::Real,
                                    years::Int,
                                    tax_scheme::Union{Nothing, TaxScheme} = nothing,
                                    population_params::PopulationParams = FixedPopulationParams(population = eligible_actors + non_eligible_actors,
                                                                                                create_actor! = m -> create_sumsy_actor!(m, sumsy = sumsy)),
                                    data_handler::DataHandler = gdp_data_handler(12 * sumsy_interval),
                                    termination_handler::Union{TerminationHandler, Nothing} = nothing,
                                    model_initialisations::Vector{<: Function} = Vector{Function}(),
                                    actor_initialisations::Vector{<: Function} = Vector{Function}(),
                                    model_adaptations::Vector{<: Function} = Vector{Function}())
    period = 12 * sumsy_interval
    sim_params = SimParams(years * period)

    if non_eligible_actors > 0
        configure_sumsy_actors! = model -> mixed_actors!(model, num_gi_actors = eligible_actors)
    else
        configure_sumsy_actors! = mixed_actors!
    end

    if non_eligible_actors > 0
        initial_wealth *= eligible_actors / (eligible_actors + non_eligible_actors)
    end


    sumsy_params = StandardSuMSyParams(sumsy_interval,
                                        sumsy_transactional,
                                        initial_wealth,
                                        initial_wealth,
                                        configure_sumsy_actors! = configure_sumsy_actors!)
    yard_sale_params = GDPYardSaleParams(gdp_period = period,
                                        gdp_per_capita = gdp_per_capita,
                                        wealth_transfer_range = wealth_transfer:wealth_transfer:wealth_transfer,
                                        minimal_wealth_transfer = 0,
                                        wealth_advantage_adjustment = waa,
                                        average_wealth = initial_wealth)


    run_sumsy_simulation(sumsy_params,
                            sim_params = sim_params,
                            population_params = population_params,
                            transaction_params = yard_sale_params,
                            tax_scheme = tax_scheme,
                            data_handler = data_handler,
                            termination_handler = termination_handler,
                            model_initialisations = model_initialisations,
                            actor_initialisations = actor_initialisations,
                            model_adaptations = model_adaptations)
end

function run_age_typed_sumsy_gdp_simulation(sumsy::SuMSy;
                                            sumsy_interval::Int = 30,
                                            sumsy_transactional::Bool = false,
                                            pop_min_18::Int = 0,
                                            pop_min_18_income::Int = 0,
                                            pop_18_65::Int = 1000,
                                            pop_18_65_income::Int = 2000,
                                            pop_65_plus::Int = 0,
                                            pop_65_plus_income::Int = 0,
                                            eligible_actors::Int = 1000,
                                            non_eligible_actors::Int = 0,
                                            initial_wealth::Real = telo(sumsy),
                                            wealth_transfer::Real = 0.2,
                                            gdp_per_capita::Real,
                                            years::Int,
                                            tax_scheme::Union{Nothing, TaxScheme} = nothing,
                                            data_handler::DataHandler = gdp_data_handler(12 * sumsy.interval),
                                            termination_handler::Union{TerminationHandler, Nothing} = nothing,
                                            model_initialisations::Vector{<: Function} = Vector{Function}(),
                                            actor_initialisations::Vector{<: Function} = Vector{Function}(),
                                            model_adaptations::Vector{<: Function} = Vector{Function}())
    population_params = AgeTypedPopulationParams(Dict(:min_18 => pop_min_18,
                                                    :age_18_65 => pop_18_65,
                                                    :age_65_plus => pop_65_plus,),
                                                m -> create_sumsy_actor!(m, sumsy = sumsy))
end

function run_consumer_supplier_simulation(sumsy::SuMSy;
                                            sumsy_interval::Int,
                                            sim_length::Int = 150,
                                            num_suppliers::Int = 1,
                                            consumers_per_supplier::Int = 100,
                                            fulfilled_demand::Int = 1,
                                            net_profit::Real = 1,
                                            suppliers_gi_eligible = false,
                                            tax_scheme::Union{Nothing, TaxScheme} = nothing,
                                            population_params = AbsoluteTypedPopulationParams(actor_numbers = Dict(:supplier => num_suppliers,
                                                                                                                    :consumer => consumers_per_supplier * num_suppliers),
                                                                                        create_actor! = m -> create_sumsy_actor!(m,
                                                                                                                                sumsy = sumsy,
                                                                                                                                initialize = false, 
                                                                                                                                sumsy_interval = sumsy_interval)),
                                            data_handler::DataHandler = full_data_handler(sumsy_interval),
                                            termination_handler::Union{TerminationHandler, Nothing} = nothing,
                                            model_initialisations::Vector{<: Function} = Vector{Function}(),
                                            actor_initialisations::Vector{<: Function} = Vector{Function}(),
                                            model_adaptations::Vector{<: Function} = Vector{Function}())
    sim_params = SimParams(sim_length * sumsy_interval)

    gi_eligible_types = suppliers_gi_eligible ? [:supplier, :consumer] : [:consumer]
    sumsy_params = create_StandardSuMSyParams(sumsy_interval = sumsy_interval,
                                                transactional = false,
                                                configure_sumsy_actors! = model -> typed_gi_actors!(model, gi_actor_types = gi_eligible_types),
                                                initial_gi_wealth = telo(sumsy))
    consumer_supply_params = FixedConsumerSupplyParams(num_suppliers = num_suppliers,
                                                        consumers_per_supplier = consumers_per_supplier,
                                                        demand = fulfilled_demand,
                                                        price = net_profit)

    return run_sumsy_simulation(sumsy_params,
                                sim_params = sim_params,
                                population_params = population_params,
                                transaction_params = consumer_supply_params,
                                tax_scheme = tax_scheme,
                                data_handler = data_handler,
                                termination_handler = termination_handler,
                                model_initialisations = model_initialisations,
                                actor_initialisations = actor_initialisations,
                                model_adaptations = model_adaptations)
end

function run_debt_based_simulation(debt_based_params::DebtBasedParams;
                                    sim_params::SimParams,
                                    transaction_params::Union{TransactionParams, Nothing} = nothing,
                                    tax_scheme::Union{Nothing, TaxScheme} = nothing,
                                    population_params::PopulationParams = FixedPopulationParams(population = 1000),
                                    data_handler::Union{DataHandler, Nothing} = nothing,
                                    termination_handler::Union{TerminationHandler, Nothing} = nothing,
                                    model_initialisations::Vector{<: Function} = Vector{Function}(),
                                    actor_initialisations::Vector{<: Function} = Vector{Function}(),
                                    model_adaptations::Vector{<: Function} = Vector{Function}())
    model = create_econo_model()

    run_simulation(model,
                    sim_params = sim_params,
                    population_params = population_params,
                    transaction_params = transaction_params, 
                    monetary_params = debt_based_params,
                    tax_scheme = tax_scheme,
                    data_handler = data_handler,
                    termination_handler = termination_handler,
                    model_initialisations = model_initialisations,
                    actor_initialisations = actor_initialisations,
                    model_adaptations = model_adaptations)
end

# Utility functions

function set_random_seed!(lock_random_generator::Bool)
    if lock_random_generator
        Random.seed!(35646516187576568)
    else
        Random.seed!(Integer(round(time())))
    end
end