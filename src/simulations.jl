using EconoSim
using Agents
using Random
using DataFrames

struct SimParams
    sim_length::Int
    collection_interval::Int
    lock_random_generator::Bool
    SimParams(sim_length::Int,
              collection_interval::Int;
              lock_random_generator::Bool = true) = new(sim_length, collection_interval, lock_random_generator)
end

# General simulation

function run_simulation(model::ABM,
                        sim_params::SimParams,
                        transaction_params::TransactionParams,
                        monetary_params::MonetaryModelParams,
                        model_adaptations::Vector{<: Function} = Vector{Function}();
                        actor_data_collectors::Vector = [equity_collector,
                                                        wealth_collector,
                                                        deposit_collector,
                                                        :types],
                        model_data_collectors::Vector = [],
                        process_data!::Function = standard_data_processing!)
    set_random_seed!(sim_params.lock_random_generator)

    model.properties[:last_transaction] = model.step
    model.properties[:collection_interval] = sim_params.collection_interval

    initialize_transaction_model!(model, transaction_params)
    initialize_monetary_model!(model, monetary_params)

    for model_adaptation in model_adaptations
        add_model_behavior!(model, model_adaptation)
    end

    actor_data, model_data = run_econo_model!(model,
                                            sim_params.sim_length,
                                            adata = actor_data_collectors,
                                            mdata = model_data_collectors,
                                            when = collect_data)

    return process_data!(actor_data, model_data)
end

# Fixed wealth simulation

function run_fixed_wealth_simulation(sim_params::SimParams,
                                    transaction_params::TransactionParams,
                                    fixed_wealth_params::FixedWealthParams,
                                    model_adaptations::Vector{<: Function} = Vector{Function}();
                                    actor_data_collectors::Vector = [equity_collector,
                                                                    wealth_collector,
                                                                    deposit_collector,
                                                                    :types],
                                    model_data_collectors::Vector = [],
                                    process_data!::Function = standard_data_processing!)
    model = create_unremovable_econo_model()

    run_simulation(model,
                    sim_params,
                    transaction_params,
                    fixed_wealth_params,
                    model_adaptations,
                    actor_data_collectors = actor_data_collectors,
                    model_data_collectors = model_data_collectors,
                    process_data! = process_data!)
end

function run_fixed_wealth_simulation(;
                                    num_actors::Int = 1000,
                                    num_transactions::Int = 200,
                                    initial_wealth::Real = 200000,
                                    sim_length::Int = 150,
                                    period::Int = 30,
                                    actor_data_collectors::Vector = [equity_collector,
                                                                    wealth_collector,
                                                                    deposit_collector,
                                                                    :types],
                                    model_data_collectors::Vector = [],
                                    process_data!::Function = standard_data_processing!)
    sim_params = SimParams(sim_length * period, period)
    fixed_wealth_params = FixedWealthParams(initial_wealth, true)
    yard_sale_params = StandardYardSaleParams(num_actors,
                                                num_transactions:num_transactions,
                                                0.2:0.2:0.2,
                                                0)

    run_fixed_wealth_simulation(sim_params,
                                yard_sale_params,
                                fixed_wealth_params,
                                actor_data_collectors = actor_data_collectors,
                                model_data_collectors = model_data_collectors,
                                process_data! = process_data!)
end

function run_fixed_wealth_gdp_simulation(;
                                        population::Int,
                                        m2::Real,
                                        gdp::Real,
                                        years::Int)
    sim_params = SimParams(years * 365, 365)
    fixed_wealth_params = FixedWealthParams(m2 / population, true)
    yard_sale_params = GDPYardSaleParams(population, gdp, 365, 0.2:0.2:0.2, 0)

    run_fixed_wealth_simulation(sim_params,
                                yard_sale_params,
                                fixed_wealth_params,
                                model_data_collectors = [gdp_collector!, transactions_collector!],
                                process_data! = gdp_data_processing!)
end

# SuMSy simulation

function run_sumsy_simulation(sumsy::SuMSy,
                                sim_params::SimParams,
                                transaction_params::TransactionParams,
                                sumsy_params::SuMSyParams,
                                model_adaptations::Vector{<: Function} = Vector{Function}();
                                actor_data_collectors::Vector = [equity_collector,
                                                                wealth_collector,
                                                                deposit_collector,
                                                                :types],
                                model_data_collectors::Vector = [],
                                process_data!::Function = standard_data_processing!)
    if sumsy.transactional
        model = create_unremovable_single_sumsy_model(sumsy)
    else
        model = create_unremovable_single_sumsy_model(sumsy, model_behaviors = process_model_sumsy!)
    end
    
    run_simulation(model,
                    sim_params,
                    transaction_params,
                    sumsy_params,
                    model_adaptations,
                    actor_data_collectors = actor_data_collectors,
                    model_data_collectors = model_data_collectors,
                    process_data! = process_data!)
end

function run_sumsy_simulation(sumsy::SuMSy;
                                eligible_actors::Int = 1000,
                                non_eligible_actors::Int = 0,
                                num_transactions::Int = 200,
                                period_length::Int = sumsy.interval,
                                sim_length::Int = 150,
                                distributed::Bool = true,
                                model_adaptation::Union{Function, Nothing} = nothing,
                                actor_data_collectors::Vector = [equity_collector,
                                                                wealth_collector,
                                                                deposit_collector,
                                                                :types],
                                model_data_collectors::Vector = [],
                                process_data!::Function = standard_data_processing!)
    sim_params = SimParams(sim_length * period_length,
                            period_length)

    initial_wealth = telo(sumsy)

    if non_eligible_actors > 0
        make_sumsy_actors! = model -> mixed_actors!(model, eligible_actors)
    else
        make_sumsy_actors! = mixed_actors!
    end

    if non_eligible_actors > 0
        initial_wealth *= eligible_actors / (eligible_actors + non_eligible_actors)
    end


    sumsy_params = SuMSyParams(initial_wealth,
                                initial_wealth,
                                make_sumsy_actors! = make_sumsy_actors!,
                                distribute_wealth! = distributed ? equal_wealth_distribution! : concentrated_wealth_distribution!)
    transaction_params = StandardYardSaleParams(eligible_actors + non_eligible_actors,
                                                num_transactions:num_transactions,
                                                0.2:0.2:0.2,
                                                0)
    model_adaptations = isnothing(model_adaptation) ? Vector{Function}() : Vector{Function}([model_adaptation])

    run_sumsy_simulation(sumsy,
                            sim_params, 
                            transaction_params,
                            sumsy_params,
                            model_adaptations,
                            actor_data_collectors = actor_data_collectors,
                            model_data_collectors = model_data_collectors,
                            process_data! = process_data!)
end

function run_consumer_supplier_simulation(sumsy::SuMSy,
                                            sim_length::Int = 150;
                                            consumers_per_supplier::Int = 100,
                                            fulfilled_demand::Int = 1,
                                            net_profit::Real = 1,
                                            suppliers_gi_eligible = false,
                                            actor_data_collectors::Vector = [equity_collector,
                                                                            wealth_collector,
                                                                            deposit_collector,
                                                                            :types],
                                            model_data_collectors::Vector = [],
                                            process_data!::Function = standard_data_processing!)
    sim_params = SimParams(sim_length * sumsy.interval, sumsy.interval)

    gi_eligible_types = suppliers_gi_eligible ? [:supplier, :consumer] : [:consumer]
    sumsy_params = SuMSyParams(telo(sumsy), make_sumsy_actors! = model -> typed_gi_actors!(model, gi_eligible_types))
    consumer_supply_params = FixedConsumerSupplyParams(1, consumers_per_supplier, fulfilled_demand, net_profit)

    return run_sumsy_simulation(sumsy,
                                sim_params,
                                consumer_supply_params,
                                sumsy_params,
                                actor_data_collectors = actor_data_collectors,
                                model_data_collectors = model_data_collectors,
                                process_data! = process_data!)
end

function run_debt_based_simulation(sim_params::SimParams,
                                    transaction_params::TransactionParams,
                                    debt_based_params::DebtBasedParams,
                                    model_adaptations::Vector{<: Function} = Vector{Function}();
                                    actor_data_collectors::Vector = [equity_collector,
                                                                    wealth_collector,
                                                                    deposit_collector,
                                                                    :types],
                                    model_data_collectors::Vector = [],
                                    process_data!::Function = standard_data_processing!)
    model = create_econo_model()
    model.properties[:bank] = Balance()

    run_model!(model,
                sim_params,
                transaction_params, 
                debt_based_params,
                model_adaptations,
                actor_data_collectors = actor_data_collectors,
                model_data_collectors = model_data_collectors,
                process_data! = process_data!)
end

# Actor data collectors

function equity_collector(actor)
    return liability_value(get_balance(actor), EQUITY)
end

function wealth_collector(actor)
    return max(CUR_0, liability_value(get_balance(actor), EQUITY))
end

function deposit_collector(actor)
    return asset_value(get_balance(actor), SUMSY_DEP)
end

function sumsy_equity_collector(actor)
    step = get_step(actor.model)
    g, d = calculate_adjustments(get_balance(actor), step)

    return liability_value(get_balance(actor), EQUITY) + g - d
end

function sumsy_wealth_collector(actor)
    return max(CUR_0, sumsy_equity_collector(actor))
end

function sumsy_deposit_collector(actor)
    return sumsy_assets(actor, get_step(actor.model))
end

function collect_data(model::ABM, step::Int)
    return mod(step, model.collection_interval) == 0
end

# Model data collectors

function gdp_collector!(model::ABM)
    gdp = model.gdp
    model.gdp = CUR_0

    return gdp
end

function transactions_collector!(model::ABM)
    transactions = model.transactions
    model.transactions = 0

    return transactions
end

# Data processing

function standard_data_processing!(actor_data, model_data)
    rename!(actor_data, 3 => :deposit_data, 4 => :equity_data, 5 => :wealth_data)

    return actor_data, model_data
end

function gdp_data_processing!(actor_data, model_data)
    actor_data, model_data = standard_data_processing!(actor_data, model_data)
    rename!(model_data, 2 => :gdp_data, 3 => :transactions_data)

    return actor_data, model_data
end

# Utility functions

function set_random_seed!(lock_random_generator::Bool)
    if lock_random_generator
        Random.seed!(35646516187576568)
    else
        Random.seed(Integer(round(time())))
    end
end