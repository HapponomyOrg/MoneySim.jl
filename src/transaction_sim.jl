using EconoSim
using Random
using Agents
using DataFrames

C_0 = Currency(0)

struct SimParams
    lock_random_generator::Bool
    sim_length::Int
    collection_interval::Int
    transaction_range::RangeData{Int}
end

abstract type MoneyModelParams end

struct FixedWealthParams <: MoneyModelParams
    num_actors::Int
    initial_wealth::Currency
    wealth_distributed::Bool
end

function run_fixed_wealth_simulation(sim_params::SimParams,
                                        fixed_wealth_params::FixedWealthParams,
                                        transaction_params::TransactionParams
                                        model_adaptations::Vector{Function} = [])
    model = create_unremovable_econo_model()
    add_actors!(model, fixed_wealth_params)
    
    run_model!(model,
                sim_params,
                transaction_params,
                model_adaptations)
end

struct SuMSyParams <: MoneyModelParams
    guaranteed_income::Currency
    demurrage_free::Currency
    demurrage_tiers::DemTiers
    transactional::Bool
    num_gi_actors::Int
    initial_gi_wealth::Currency
    num_non_gi_actors::Int
    initial_non_gi_wealth::Currency
    wealth_concentrated::Bool
end

function run_sumsy_simulation(sim_params::SimParams,
                                sumsy_params::SuMSyParams,
                                transaction_params::TransactionParams,
                                model_adaptations::Vector{Function} = [])
    sumsy = SuMSy(sumsy_params.guaranteed_income,
                    sumsy_params.demurrage_free,
                    sumsy_params.demurrage_tiers,
                    30,
                    transactional = sumsy_params.transactional)

    if sumsy.transactional
        model = create_unremovable_single_sumsy_model(sumsy)
    else
        model = create_unremovable_single_sumsy_model(sumsy, model_behaviors = process_model_sumsy!)
    end

    add_sumsy_actors!(model, sumsy_params)
    run_model!(model, sim_params, transaction_params, model_adaptations)
end

struct DebtBasedParams <: MoneyModelParams
    num_actors::Int
    initial_wealth::Currency
end

function run_debt_based_simulation(sim_params::SimParams,
                                    debt_based_params::DebtBasedParams,
                                    transaction_params::TransactionParams,
                                    model_adaptations::Vector{Function} = [])
end

function add_actors(model::ABM, money_params::MoneyModelParams)
    if !money_params.wealth_distributed
        total_wealth = money_params.num_actors * money_params.initial_wealth
        initial_wealth = C_0
    else
        initial_wealth = money_params.initial_wealth
    end

    for i in 1:num_actors
        actor = add_actor!(model, MonetaryActor())
        actor.model = model
        book_asset!(get_balance(actor), SUMSY_DEP, initial_wealth)
    end
    
    if !money_params.wealth_distributed
        actor = random_agent(model)
        book_asset!(get_balance(actor), SUMSY_DEP, total_wealth)
    end

    return model
end

function add_sumsy_actors!(model::ABM, sumsy_params::SuMSyParams)
    if !sumsy_params.wealth_distributed
        total_wealth = sumsy_params.num_gi_actors
                        * sumsy_params.initial_gi_wealth
                        + sumsy_params.num_non_gi_actors
                        * sumsy_paramsinitial_non_gi_wealth
        initial_gi_wealth = C_0
        initial_non_gi_wealth = C_0
    else
        initial_gi_wealth = sumsy_params.initial_gi_wealth
        initial_non_gi_wealth = sumsy_params.initial_non_gi_wealth
    end

    for actors_tuples in [(sumsy_params.num_gi_actors, true, initial_gi_wealth),
                            (sumsy_params.num_non_gi_actors, false, initial_non_gi_wealth)]
        for actor_tuple in actors_tuples
            gi_eligible = actor_tuple[2]
            initial_wealth = actor_tuple[3]

            for i in 1:actor_tuple[1]
                actor = add_single_sumsy_actor!(model, gi_eligible = gi_eligible, initialize = false)

                actor.model = model
                book_asset!(get_balance(actor), SUMSY_DEP, initial_wealth)
            end
        end
    end

    if !sumsy_params.wealth_distributed
        actor = random_agent(model)
        book_asset!(get_balance(actor), SUMSY_DEP, total_wealth)
    end

    return model
end

function run_model!(model::ABM,
                    sim_params::SimParams,
                    transaction_params::TransactionParams,
                    model_adaptations::Vector{Function} = [])
    set_random_seed(sim_params.lock_random_generator)
                
    model.properties[:transaction_range] = sim_params.transaction_range
    model.properties[:last_transaction] = model.step
    model.properties[:collection_interval] = sim_params.collection_interval
    model.properties[:transaction_params] = transaction_params

    if typeof(transaction_params) == YardSaleParams
        add_model_behavior!(model, yard_sale!)
    elseif typeof(transaction_params) == TaxedYardSaleParams
        add_model_behavior!(model, taxed_yard_sale!)
    elseif typeof(transaction_params) == ConsumerSupplierParams
    end

    for model_adaptation in model_adaptations
        add_model_behavior!(model, model_adaptation)
    end

    data, _ = run_econo_model!(model,
                                sim_length,
                                adata = [deposit_data, equity_data, wealth_data],
                                when = collect_data)

    return data
end

function set_random_seed(lock_random_generator::Bool)
    if lock_random_generator
        Random.seed!(3564651616568)
    else
        Random.seed(Integer(round(time())))
    end
end

function equity_data(actor)
    return liability_value(get_balance(actor), EQUITY)
end

function wealth_data(actor)
    return max(CUR_0, liability_value(get_balance(actor), EQUITY))
end

function deposit_data(actor)
    return asset_value(get_balance(actor), SUMSY_DEP)
end

function collect_data(model::ABM, step::Int)
    return mod(step, model.collection_interval) == 0
end