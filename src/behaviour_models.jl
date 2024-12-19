using Agents
using FixedPointDecimals
using EconoSim
using Random

abstract type BehaviourParams{C <: FixedDecimal} end

function adjusted_asset_value!(actor::BalanceActor)
    balance = get_balance(actor)

    if balance isa SuMSyBalance && is_transactional(balance)
        adjust_sumsy_balance!(balance, actor.model.step)
    end

    return asset_value(balance, SUMSY_DEP)
end

# Yard sale model
abstract type YardSaleParams{C <: FixedDecimal} <: BehaviourParams{C} end

struct StandardYardSaleParams{C <: FixedDecimal} <: YardSaleParams{C}
    transaction_range::UnitRange{Int}
    wealth_transfer_range::StepRange{Percentage, Percentage}
    minimal_wealth_transfer::C
    remove_broke_actors::Bool
    StandardYardSaleParams(transfer_range::UnitRange{Int},
                            wealth_transfer_range::Union{StepRange, StepRangeLen},
                            minimal_wealth_transfer::Real,
                            remove_broke_actors::Bool) = new{Currency}(transfer_range,
                                                                        wealth_transfer_range,
                                                                        minimal_wealth_transfer,
                                                                        remove_broke_actors)
end

"""
struct GDPYardSaleParams{C <: FixedDecimal} <: YardSaleParams{C}
    * gdp_period::Int - The number of cycles per GDP period.
    * gdp_per_capita::C - The GDP per actor over a period.
    * wealth_transfer_range::StepRange{Percentage, Percentage} - The range of percentage values to be used in the wealth transfer.
    * minimal_wealth_transfer::C - The minimal amount of wealth that needs to be transferred.
    * remove_broke_actors::Bool - Whether or not to remove actors that have gone broke.
    * gdp_model_behavior - The function that is used to execute the transactions.
"""
struct GDPYardSaleParams{C <: FixedDecimal, F} <: YardSaleParams{C}
    gdp_period::Int
    gdp_per_capita::C
    wealth_transfer_range::StepRange{Percentage, Percentage}
    minimal_wealth_transfer::C
    remove_broke_actors::Bool
    gdp_model_behavior::F
    GDPYardSaleParams(gdp_period::Int,
                        gdp_per_capita::Real,
                        wealth_transfer_range::Union{StepRange, StepRangeLen},
                        minimal_wealth_transfer::Real,
                        remove_broke_actors::Bool,
                        gdp_model_behavior) = new{Currency, typeof(gdp_model_behavior)}(gdp_period,
                                                                                        gdp_per_capita,
                                                                                        wealth_transfer_range,
                                                                                        minimal_wealth_transfer,
                                                                                        remove_broke_actors,
                                                                                        gdp_model_behavior)
end

function initialize_behaviour_model!(model::ABM, params::StandardYardSaleParams)
    initialize_yard_sale!(model, params)

    abmproperties(model)[:transaction_range] = params.transaction_range
    
    add_model_behavior!(model, yard_sale!, position = 1)
end

function initialize_behaviour_model!(model::ABM, params::GDPYardSaleParams)
    initialize_yard_sale!(model, params)
    properties = abmproperties(model)

    properties[:gdp] = params.gdp_per_capita * nagents(model)
    properties[:gdp_period] = params.gdp_period
    properties[:min_gdp_per_cycle] = model.gdp / model.gdp_period
    properties[:transactions] = 0
    properties[:min_transaction] = typemax(Currency)
    properties[:max_transaction] = typemin(Currency)

    add_model_behavior!(model, params.gdp_model_behavior, position = 1)
end

function initialize_yard_sale!(model::ABM, params::YardSaleParams)
    properties = abmproperties(model)

    properties[:wealth_transfer_range] = params.wealth_transfer_range
    properties[:minimal_wealth_transfer] = params.minimal_wealth_transfer
    properties[:non_broke_actor_ids] = Vector{Int}(undef, nagents(model))
    properties[:remove_broke_actors] = params.remove_broke_actors

    # Calculate broke threshold
    if params.minimal_wealth_transfer > 0
        properties[BROKE_THRESHOLD] = CUR_0
    else
        min_transfer_rate = first(params.wealth_transfer_range)
        increment = Currency(1)

        for _ in 1:get_currency_precision(increment)
            increment *= Currency(0.1)
        end

        transfer_amount = CUR_0
        broke_threshold = CUR_0

        while transfer_amount == CUR_0
            broke_threshold += increment
            transfer_amount = Currency(min_transfer_rate * broke_threshold)
        end

        properties[BROKE_THRESHOLD] = broke_threshold
    end

    i = 1

    for actor in allagents(model)
        model.non_broke_actor_ids[i] = actor.id
        i += 1
    end
end

function yard_sale!(model::ABM)
    transactions = rand(model.transaction_range)

    for _ in 1:transactions
        if length(model.non_broke_actor_ids) > 1
            atomic_yard_sale!(model)
        else
            break
        end
    end
end

"""
    gdp_initialyard_sale!(model::ABM)

    Executes the yard sale for the first `gdp_period` of the simulation, making sure that GDP is reached over the period.
    During this first period, 10 times the maximum number of transactions per cycle needed to reach GDP per cycle is stored.
    The multiplier of 10 gives some time to reach GDP should the average amount per transaction diominish over time.
    After the first period, the model will switch to the `gdp_constrained_yard_sale!` function.
    Real GDP per period is stored in the model.
"""
function gdp_baseline_yard_sale!(model::ABM)
    gdp_yard_sale!(model)

    if model.step % model.gdp_period == 0
        abmproperties(model)[:max_transactions] = 10 * model.transactions
        delete_model_behavior!(model, gdp_baseline_yard_sale!)
        add_model_behavior!(model, gdp_constrained_yard_sale!)
    end
end

"""
    gdp_constrained_yard_sale!(model::ABM)

    Executes the yard sale model for each period after the first one,
    attempting to reach GDP per cycle if it can be reached with no more than `max_transactions`,
    stored during the execution of 'gdp_baseline_yard_sale!'.
    Real GDP per period is stored in the model.
"""
function gdp_constrained_yard_sale!(model::ABM)
    gdp_yard_sale!(model, x -> x < model.max_transactions)
end

"""
    gdp_yard_sale!!(model::ABM, additional_clause = true)

    Executes the yard sale model for each period, making sure that GDP is reached over each period.
        * model::ABM - the model
        * transactions_constraint - utility function to control the transaction loop.
                                    It takes the current number of transactions as a parameter. If it returns false, the loop will be stopped.
"""
function gdp_yard_sale!(model::ABM, transactions_constraint = x -> true)
    cycle_gdp = 0
    transactions = 0
    min_transaction = model.min_transaction
    max_transaction = model.max_transaction 

    while cycle_gdp < model.min_gdp_per_cycle && length(model.non_broke_actor_ids) > 1 && transactions_constraint(transactions)
        _, _, amount = atomic_yard_sale!(model)
        cycle_gdp += amount
        transactions += 1
        min_transaction = min(min_transaction, amount)
        max_transaction = max(max_transaction, amount)
    end

    model.gdp += cycle_gdp
    model.transactions += transactions
    model.min_transaction = min_transaction
    model.max_transaction = max_transaction
end

function atomic_yard_sale!(model::ABM)
    # Make sure two different random agents are picked.
    non_broke_actor_ids = model.non_broke_actor_ids
    num_non_broke_actors = length(non_broke_actor_ids)

    target_index_1 = rand(1:num_non_broke_actors)
    target_id_1 = non_broke_actor_ids[target_index_1]
    target1 = model[target_id_1]

    target_index_2 = rand(1:num_non_broke_actors - 1)
    target_id_2 = remove_index(non_broke_actor_ids, target_index_1)[target_index_2]
    target2 = model[target_id_2]

    source, destination, amount = yard_sale_transfer!(target1, target2, model)
    
    transfer_asset!(model, source, destination, SUMSY_DEP, amount)

    if hasproperty(destination, :income)
        destination.income += amount
    else
        destination.income = amount
    end

    if hasproperty(model, :tax_scheme)
        model.tax_scheme.collect_vat!(destination, amount)
    end

    if model.remove_broke_actors
        if is_broke(target1)
            deleteat!(non_broke_actor_ids, findall(x -> x == target_id_1, non_broke_actor_ids)[1])
        end

        if is_broke(target2)
            deleteat!(non_broke_actor_ids, findall(x -> x == target_id_2, non_broke_actor_ids)[1])
        end
    end

    return source, destination, amount
end

function yard_sale_transfer!(target1::AbstractActor,
                                target2::AbstractActor,
                                model::ABM)
    transfer_rate = rand(model.wealth_transfer_range)

    av1 = max(CUR_0, adjusted_asset_value!(target1))
    av2 = max(CUR_0, adjusted_asset_value!(target2))

    return randomize_direction(target1,
                                av1,
                                target2,
                                av2,
                                transfer_rate,
                                model.minimal_wealth_transfer)
end

function randomize_direction(target1::AbstractActor,
                            av1::Real,
                            target2::AbstractActor,
                            av2::Real,
                            transfer_rate::Real,
                            mininal_transfer::Real)
    min_balance = min(av1, av2)
    transfer = max(min(min_balance, mininal_transfer),
            Currency(min_balance * transfer_rate))

    if rand(1:2) == 1
        source = target1
        destination = target2
    else
        source = target2
        destination = target1
    end

    return source, destination, transfer
end

# Consumer/Supplier model
# Consumer supply models create actors based on the number of suppliers and the number of consumers per supplier.
# It is advised to work with a FixedPopulationParams model that is initoialized with a popilation of 0.

abstract type ConsumerSupplyParams{C <: FixedDecimal} <: BehaviourParams{C} end

struct FixedConsumerSupplyParams{C <: FixedDecimal} <: ConsumerSupplyParams{C}
    num_suppliers::Integer
    consumers_per_supplier::Integer
    demand::Integer
    price::C
    FixedConsumerSupplyParams(num_suppliers::Integer,
                                consumers_per_supplier::Integer,
                                demand::Integer,
                                price::Real) = new{Currency}(num_suppliers,
                                                                consumers_per_supplier,
                                                                demand,
                                                                price)
end

struct VariableConsumerSupplierParams{C <: FixedDecimal} <: ConsumerSupplyParams{C}
    num_suppliers::Integer
    consumers_per_supplier::UnitRange{Int}
    demand::UnitRange{Int}
    price::StepRange{C, C}
    VariableConsumerSupplierParams(num_suppliers::Integer,
                                    consumers_per_supplier::UnitRange{Int},
                                    demand_quantity::UnitRange{Int},
                                    price::StepRange{Real, Real}) = new{Currency}(num_suppliers,
                                                                                    consumers_per_supplier,
                                                                                    demand_quantity,
                                                                                    price)
end

function initialize_behaviour_model!(model::ABM, params::FixedConsumerSupplyParams)
    price() = params.price
    num_consumers() = params.consumers_per_supplier
    demand() = params.demand

    add_suppliers!(params.num_suppliers, price, num_consumers, demand, model)
end

function initialize_behaviour_model!(model::ABM, params::VariableConsumerSupplierParams)
    price() = rand(params.price)
    num_consumers() = rand(params.consumers_per_supplier)
    demand() = rand(params.demand)

    add_suppliers!(params.num_suppliers, price, num_consumers, demand, model)
end

function add_suppliers!(num_suppliers::Int, price, num_consumers, demand, model::ABM)
    for i in 1:num_suppliers
        supplier = add_actor!(model, model.create_actor!(model))
        add_type!(supplier, :supplier)
        supplier.price = price()
        supplier.model = model

        add_consumers!(supplier, num_consumers, demand, model)
    end
end

function add_consumers!(supplier::BalanceActor, num_consumers, demand, model::ABM)
    for i in 1:num_consumers()
        consumer = add_actor!(model, model.create_actor!(model))
        add_type!(consumer, :consumer)
        add_behavior!(consumer, satisfy_demand!)
        consumer.supplier = supplier
        consumer.demand = demand
    end
end

function satisfy_demand!(model::ABM, actor::BalanceActor)
    available = adjusted_asset_value!(actor)
    demand = actor.demand()
    price = actor.supplier.price

    while demand * price > available
        demand -= 1
    end

    transfer_asset!(get_balance(actor),
                    get_balance(actor.supplier),
                    SUMSY_DEP,
                    demand * price,
                    timestamp = model.step)
end