using EconoSim
using Random
using Agents
using DataFrames

struct SimParams
    lock_random_generator::Bool
    sim_length::Int
    collection_interval::Int
    transaction_range::UnitRange{Int}
end

abstract type MoneyModelParams{C <: FixedDecimal} end

struct FixedWealthParams{C <: FixedDecimal} <: MoneyModelParams{C}
    num_actors::Int
    initial_wealth::C
    wealth_distributed::Bool
    FixedWealthParams(num_actors::Int,
                        initial_wealth::Real,
                        wealth_distributed::Bool) = new{Currency}(num_actors, initial_wealth, wealth_distributed)
end

function run_fixed_wealth_simulation(sim_params::SimParams,
                                        fixed_wealth_params::FixedWealthParams,
                                        transaction_params::TransactionParams,
                                        model_adaptations::Vector{<: Function} = Vector{Function}())
    model = create_unremovable_econo_model()
    add_actors!(model, fixed_wealth_params)
    
    run_model!(model,
                sim_params,
                transaction_params,
                model_adaptations)
end

struct SuMSyParams{C <: FixedDecimal} <: MoneyModelParams{C}
    guaranteed_income::C
    demurrage_free::C
    demurrage_tiers::DemTiers
    transactional::Bool
    num_gi_actors::Int
    initial_gi_wealth::C
    num_non_gi_actors::Int
    initial_non_gi_wealth::C
    wealth_distributed::Bool
    SuMSyParams(guaranteed_income::Real,
                demurrage_free::Real,
                demurrage_tiers::Union{DemTiers, DemSettings, Real},
                transactional::Bool,
                num_gi_actors::Int,
                initial_gi_wealth::Real,
                num_non_gi_actors::Int,
                initial_non_gi_wealth::Real,
                wealth_distributed::Bool) = new{Currency}(guaranteed_income,
                                                            demurrage_free,
                                                            make_tiers(demurrage_tiers),
                                                            transactional,
                                                            num_gi_actors,
                                                            initial_gi_wealth,
                                                            num_non_gi_actors,
                                                            initial_non_gi_wealth,
                                                            wealth_distributed)
end

function run_sumsy_simulation(sim_params::SimParams,
                                sumsy_params::SuMSyParams,
                                transaction_params::TransactionParams,
                                model_adaptations::Vector{<: Function} = Vector{Function}())
    sumsy = SuMSy(sumsy_params.guaranteed_income,
                    sumsy_params.demurrage_free,
                    sumsy_params.demurrage_tiers,
                    sim_params.collection_interval,
                    transactional = sumsy_params.transactional)

    if sumsy.transactional
        model = create_unremovable_single_sumsy_model(sumsy)
    else
        model = create_unremovable_single_sumsy_model(sumsy, model_behaviors = process_model_sumsy!)
    end
    
    add_sumsy_actors!(model, sumsy_params)
    run_model!(model, sim_params, transaction_params, model_adaptations,
                equity = sumsy_equity_collector,
                wealth = sumsy_wealth_collector,
                deposit = sumsy_deposit_collector)
end

struct DebtBasedParams{C <: FixedDecimal} <: MoneyModelParams{C}
    num_actors::Int
    initial_wealth::C
    DebtBasedParams(num_actors::Int,
                    initial_wealth::Real) = new{Currency}(num_actors,
                                                            initial_wealth)
end

function run_debt_based_simulation(sim_params::SimParams,
                                    debt_based_params::DebtBasedParams,
                                    transaction_params::TransactionParams,
                                    model_adaptations::Vector{<: Function} = Vector{Function}())
    set_random_seed!()
    model = create_econo_model()
    model.properties[:sumsy_base] = sumsy_base
    model.properties[:bank] = Balance()    
    start_balance = telo(sumsy_base)
    model.properties[:num_transactions] = num_transactions
    model.properties[:last_transaction] = model.step

    add_actors!(model, num_actors, start_balance,
                concentrated = concentrated,
                activate_sumsy = false)

    for actor in allagents(model)
        actor.debts = []
    end

    add_model_behavior!(model, transaction_model)

    if model_action !== nothing
        add_model_behavior!(model, model_action)
    end

    data, _ = run_econo_model!(model, sim_length, adata = [deposit_data, equity_data, wealth_data])

    return data
end

function add_actors!(model::ABM, money_params::MoneyModelParams)
    if !money_params.wealth_distributed
        total_wealth = money_params.num_actors * money_params.initial_wealth
        initial_wealth = CUR_0
    else
        initial_wealth = money_params.initial_wealth
    end

    for i in 1:money_params.num_actors
        actor = add_actor!(model, MonetaryActor())
        actor.model = model
        book_asset!(get_balance(actor), SUMSY_DEP, money_params.initial_wealth)
    end
    
    if !money_params.wealth_distributed
        actor = random_agent(model)
        book_asset!(get_balance(actor), SUMSY_DEP, total_wealth)
    end

    return model
end

function add_sumsy_actors!(model::ABM, sumsy_params::SuMSyParams)
    if !sumsy_params.wealth_distributed
        total_wealth = sumsy_params.num_gi_actors *
                        sumsy_params.initial_gi_wealth +
                        sumsy_params.num_non_gi_actors *
                        sumsy_params.initial_non_gi_wealth
        initial_gi_wealth = CUR_0
        initial_non_gi_wealth = CUR_0
    else
        initial_gi_wealth = sumsy_params.initial_gi_wealth
        initial_non_gi_wealth = sumsy_params.initial_non_gi_wealth
    end

    for actor_tuple in [(sumsy_params.num_gi_actors, true, initial_gi_wealth),
                            (sumsy_params.num_non_gi_actors, false, initial_non_gi_wealth)]
        gi_eligible = actor_tuple[2]
        initial_wealth = actor_tuple[3]

        for i in 1:actor_tuple[1]
            actor = add_single_sumsy_actor!(model, gi_eligible = gi_eligible, initialize = false)

            actor.model = model
            book_asset!(get_balance(actor), SUMSY_DEP, initial_wealth)
        end
    end

    if !sumsy_params.wealth_distributed
        actor = random_agent(model)
        book_asset!(get_balance(actor), SUMSY_DEP, total_wealth)
    end

    return model
end

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

function run_model!(model::ABM,
                    sim_params::SimParams,
                    transaction_params::TransactionParams,
                    model_adaptations::Vector{<: Function} = Vector{Function}();
                    equity::Function = equity_collector,
                    wealth::Function = wealth_collector,
                    deposit::Function = deposit_collector)
    set_random_seed!(sim_params.lock_random_generator)
                
    model.properties[:transaction_range] = sim_params.transaction_range
    model.properties[:last_transaction] = model.step
    model.properties[:collection_interval] = sim_params.collection_interval
    model.properties[:transaction_params] = transaction_params

    if transaction_params isa YardSaleParams
        add_model_behavior!(model, yard_sale!)
    elseif transaction_params isa TaxedYardSaleParams
        add_model_behavior!(model, taxed_yard_sale!)
    elseif transaction_params isa ConsumerSupplierParams
    end

    for model_adaptation in model_adaptations
        add_model_behavior!(model, model_adaptation)
    end

    data, _ = run_econo_model!(model,
                                sim_params.sim_length,
                                adata = [deposit, equity, wealth],
                                when = collect_data)

    rename!(data, 3 => :deposit_data, 4 => :equity_data, 5 => :wealth_data)
    return data
end

function set_random_seed!(lock_random_generator::Bool)
    if lock_random_generator
        Random.seed!(35646516187576568)
    else
        Random.seed(Integer(round(time())))
    end
end