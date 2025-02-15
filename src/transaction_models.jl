using Agents
using FixedPointDecimals
using EconoSim
using Random
# Temp code
#  using DataFrames
#  using CSV
# End temp code

function adjusted_asset_value!(actor::BalanceActor)
    balance = get_balance(actor)

    if balance isa SuMSyBalance && is_transactional(balance)
        adjust_sumsy_balance!(balance, actor.model.step)
    end

    return asset_value(balance, SUMSY_DEP)
end

function add_income!(actor, amount::Real)
    actor.income += amount
    actor.data_income += amount
end

function add_expenses!(actor, amount::Real)
    actor.expenses += amount
    actor.data_expenses += amount
end

function reset_income_expenses!(model)
    for actor in allagents(model)
        actor.income = CUR_0
        actor.expenses = CUR_0
    end
end

"""
    abstract type TransactionParams{C <: FixedDecimal}

Abstract type for transaction models.
    All transaction models must add an income and expenses field to the actors of the model.
    These fields must be reset at the beginning of each cycle.
    The values must not be adjusted outside the transaction model.
"""

abstract type TransactionParams end

"""
    struct BareBonesParams{C <: FixedDecimal} <: TransactionParams

    * execute_transaction! - The function that executes the transactions, if any.
                                It must accept a model as a parameter.
"""
struct BareBonesParams{F} <: TransactionParams
    execute_transaction!::F
    BareBonesParams(execute_transaction!::Union{Callable, Nothing} = nothing) = new{typeof(execute_transaction!)}(execute_transaction!)
end

function initialize_transaction_model!(model::ABM, params::BareBonesParams)
    for actor in allagents(model)
        actor.income = CUR_0
        actor.expenses = CUR_0
        actor.data_income = CUR_0
        actor.data_expenses = CUR_0
    end

    if !isnothing(params.execute_transaction!)
        add_model_behavior!(model, params.execute_transaction!)
    end
end

# Yard sale model
abstract type YardSaleParams <: TransactionParams end

struct StandardYardSaleParams{C <: FixedDecimal, DF <: Callable, AF} <: YardSaleParams
    transaction_range::UnitRange{Int}
    wealth_transfer_range::StepRange{Percentage, Percentage}
    minimal_wealth_transfer::C
    remove_broke_actors::Bool
    determine_direction::DF
    adjust_income!::AF
    StandardYardSaleParams(transaction_range::UnitRange{Int},
                            wealth_transfer_range::Union{StepRange, StepRangeLen},
                            minimal_wealth_transfer::Real,
                            remove_broke_actors::Bool,
                            determine_direction::Function = coinflip,
                            adjust_income!::Union{Callable, Nothing} = nothing) = new{Currency,
                                                                                        typeof(determine_direction),
                                                                                        typeof(adjust_income!)}(
                                                                            transaction_range,
                                                                            wealth_transfer_range,
                                                                            minimal_wealth_transfer,
                                                                            remove_broke_actors,
                                                                            determine_direction,
                                                                            adjust_income!)
end

"""
struct GDPYardSaleParams{C <: FixedDecimal} <: YardSaleParams{C}
    * gdp_period::Int - The number of cycles per GDP period.
    * gdp_per_capita::C - The GDP per actor over a period.
    * wealth_transfer_range::StepRange{Percentage, Percentage} - The range of percentage values to be used in the wealth transfer.
    * minimal_wealth_transfer::C - The minimal amount of wealth that needs to be transferred.
    * remove_broke_actors::Bool - Whether or not to remove actors that have gone broke.
    * yard_sale! - The function that determines the direction and amount of each transaction, based on the other parameters.
"""
struct GDPYardSaleParams{C <: FixedDecimal, DF <: Callable, AF} <: YardSaleParams
    gdp_period::Int
    gdp_per_capita::C
    wealth_transfer_range::StepRange{Percentage, Percentage}
    minimal_wealth_transfer::C
    remove_broke_actors::Bool
    determine_direction::DF
    adjust_income!::AF
    GDPYardSaleParams(;gdp_period::Int,
                        gdp_per_capita::Real,
                        wealth_transfer_range::Union{StepRange, StepRangeLen},
                        minimal_wealth_transfer::Real,
                        remove_broke_actors::Bool,
                        determine_direction::Function = coinflip,
                        adjust_income!::Union{Callable, Nothing} = nothing) = new{Currency,
                                                                                    typeof(determine_direction),
                                                                                    typeof(adjust_income!)}(
                                                                        gdp_period,
                                                                        gdp_per_capita,
                                                                        wealth_transfer_range,
                                                                        minimal_wealth_transfer,
                                                                        remove_broke_actors,
                                                                        determine_direction,
                                                                        adjust_income!)
end

"""
struct GDPTypedYardSaleParams{C <: FixedDecimal} <: YardSaleParams{C}
    * gdp_period::Int - The number of cycles per GDP period.
    * gdp_per_capita::C - The GDP per actor over a period.
    * wealth_transfer_range::Dict{Symbol, StepRange{Percentage, Percentage}} - The range of percentage values to be used in the wealth transfer.
    * income_probabliity::Dict{Symbol, Real} - The probability of income for each actor type.
    * remove_broke_actors::Bool - Whether or not to remove actors that have gone broke.
    * yard_sale! - The function that determines the direction and amount of each transaction, based on the other parameters.
"""
struct GDPTypedYardSaleParams{C <: FixedDecimal, DF <: Callable, AF} <: YardSaleParams
    gdp_period::Int
    gdp_per_capita::C
    wealth_transfer_range::Dict{Symbol, StepRange{Percentage, Percentage}}
    income_probabliity::Dict{Symbol, Real}
    remove_broke_actors::Bool
    determine_direction::DF
    adjust_income!::AF
    GDPTypedYardSaleParams(;gdp_period::Int,
                            gdp_per_capita::Real,
                            wealth_transfer_range::Dict{Symbol, Union{StepRange, StepRangeLen}},
                            income_probabliity::Dict{Symbol, Real},
                            remove_broke_actors::Bool,
                            determine_direction::Function = coinflip,
                            adjust_income!::Union{Callable, Nothing} = nothing) = new{Currency,
                                                                                        typeof(determine_direction),
                                                                                        typeof(adjust_income!)}(
                                                                            gdp_period,
                                                                            gdp_per_capita,
                                                                            wealth_transfer_range,
                                                                            income_probabliity,
                                                                            remove_broke_actors,
                                                                            determine_direction,
                                                                            adjust_income!)
end

function initialize_transaction_model!(model::ABM, params::StandardYardSaleParams)
    initialize_yard_sale!(model, params)

    abmproperties(model)[:transaction_range] = params.transaction_range
    
    add_model_behavior!(model,
                        x -> yard_sale!(x, params.determine_direction, params.adjust_income!))
end

function add_gdp_properties!(model::ABM, params::YardSaleParams)
    initialize_yard_sale!(model, params)
    properties = abmproperties(model)

    properties[:data_gdp] = params.gdp_per_capita * nagents(model)
    properties[:gdp_period] = params.gdp_period
    properties[:current_gdp_cycle] = 1
    properties[:gdp] = CUR_0
    properties[:min_gdp_per_cycle] = model.data_gdp / model.gdp_period
    properties[:data_transactions] = 0
    properties[:data_min_transaction] = typemax(Currency)
    properties[:data_max_transaction] = typemin(Currency)
end

function initialize_transaction_model!(model::ABM, params::GDPYardSaleParams)
    add_gdp_properties!(model, params)
    add_model_behavior!(model, x -> gdp_yard_sale!(x, params.determine_direction, params.adjust_income!))
end

function initialize_transaction_model!(model::ABM, params::GDPTypedYardSaleParams)
    add_gdp_properties!(model, params)
    add_model_behavior!(model, x -> gdp_yard_sale!(x, params.determine_direction, params.adjust_income!))
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
        actor.income = CUR_0
        actor.expenses = CUR_0
        actor.data_income = CUR_0
        actor.data_expenses = CUR_0
        model.non_broke_actor_ids[i] = actor.id
        i += 1
    end
end

function yard_sale!(model::ABM,
                    determine_direction::Function,
                    adjust_income!::Union{Callable, Nothing})
    reset_income_expenses!(model)

    if !isnothing(adjust_income!)
        adjust_income!(model)
    end

    transactions = rand(model.transaction_range)

    for _ in 1:transactions
        if length(model.non_broke_actor_ids) > 1
            atomic_yard_sale!(model, determine_direction,)
        else
            break
        end
    end
end

"""
    gdp_yard_sale!!(model::ABM, additional_clause = true)

    Executes the yard sale model for each period, making sure that GDP is reached over each period.
        * model::ABM - the model
        * transactions_constraint - utility function to control the transaction loop.
                                    It takes the current number of transactions as a parameter. If it returns false, the loop will be stopped.
"""
function gdp_yard_sale!(model::ABM,
                        determine_direction::Function,
                        adjust_income!::Union{Callable, Nothing})
    reset_income_expenses!(model)

    if !isnothing(adjust_income!)
        adjust_income!(model)
    end

    gdp = model.gdp
    transactions = 0

    # This can raise this cycle's GDP above the limit of model.min_gdp_per_cycle.
    for actor in allagents(model)
        income = actor.income
        gdp += income

        if income > 0
            transactions += 1
        end
    end

    model.data_transactions += transactions

    amount = 0
    min_transaction = model.data_min_transaction
    max_transaction = model.data_max_transaction
    max_gdp = model.min_gdp_per_cycle * model.current_gdp_cycle

    while gdp < max_gdp && length(model.non_broke_actor_ids) > 1
        _, _, amount = atomic_yard_sale!(model, determine_direction)
        gdp += amount
        min_transaction = min(min_transaction, amount)
        max_transaction = max(max_transaction, amount)
    end

    model.data_min_transaction = min_transaction
    model.data_max_transaction = max_transaction

    # Temp code
    # gdp_data = DataFrame(cycle = "s" * string(get_step(model)),
    #                         gdp_period = model.gdp_period,
    #                         gdp_cycle = model.current_gdp_cycle,
    #                         gdp = gdp,
    #                         max_gdp = max_gdp,
    #                         last_amount = amount,
    #                         max_transaction = max_transaction)
    # CSV.write("/Users/stef/Programming/Visual Studio/MoneySim.jl/data/gdp_data.csv", gdp_data, append = get_step(model) > 1)
    # End temp code

    model.data_gdp += gdp - model.gdp

    # Set the next GDP cycle number
    if mod(model.current_gdp_cycle, model.gdp_period) == 0
        model.gdp = CUR_0
        model.current_gdp_cycle = 1
    else
        model.gdp += gdp - model.gdp
        model.current_gdp_cycle += 1
    end
end

function atomic_yard_sale!(model::ABM,
                            determine_direction::Function)
    # Make sure two different random agents are picked.
    non_broke_actor_ids = model.non_broke_actor_ids
    num_non_broke_actors = length(non_broke_actor_ids)

    target_index_1 = rand(1:num_non_broke_actors)
    target_id_1 = non_broke_actor_ids[target_index_1]
    target1 = model[target_id_1]

    target_index_2 = rand(1:num_non_broke_actors - 1)
    target_id_2 = remove_index(non_broke_actor_ids, target_index_1)[target_index_2]
    target2 = model[target_id_2]

    source, destination, amount = yard_sale_transfer(model, target1, target2, determine_direction)
    
    transfer_asset!(model, source, destination, SUMSY_DEP, amount)
    add_expenses!(source, amount)
    add_income!(destination, amount)
    model.data_transactions += 1

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

function yard_sale_transfer(model::ABM,
                            target1::AbstractActor,
                            target2::AbstractActor,
                            determine_direction::Function = coinflip)
    transfer_rate = rand(model.wealth_transfer_range)

    av1 = max(CUR_0, adjusted_asset_value!(target1))
    av2 = max(CUR_0, adjusted_asset_value!(target2))

    min_balance = min(av1, av2)
    amount = max(min(min_balance, model.minimal_wealth_transfer),
            Currency(min_balance * transfer_rate))

    source, destination = determine_direction(target1, av1, target2, av2)
    
    # Temp code
    # gdp_data = DataFrame(cycle = cycle = "s" * string(get_step(model)), amount = amount, bal_1 = av1, bal_2 = av2)
    # CSV.write("/Users/stef/Programming/Visual Studio/MoneySim.jl/data/transactions.csv",
    #             gdp_data,
    #             append = get_step(model) > 1 || model.data_transactions > 1)
    # End temp code

    return source, destination, amount
end

function coinflip(target_1::AbstractActor,
                    asset_value_1::Currency,
                    target_2::AbstractActor,
                    asset_value_2::Currency)
    if rand(1:2) == 1
        source = target_1
        destination = target_2
    else
        source = target_2
        destination = target_1
    end

    return source, destination
end

function wealth_weighted_direction(target_1::AbstractActor,
                                    asset_value_1::Currency,
                                    target_2::AbstractActor,
                                    asset_value_2::Currency,
                                    wealth_factor::Real = 1.0)
    probabliity_1_to_2 = (asset_value_1 - asset_value_2) / max(asset_value_1, asset_value_2) * wealth_factor / 2 + 0.5

    if rand() <= probabliity_1_to_2
        source = target_1
        destination = target_2
    else
        source = target_2
        destination = target_1
    end
end

# Consumer/Supplier model
# Consumer supply models create actors based on the number of suppliers and the number of consumers per supplier.
# It is advised to work with a FixedPopulationParams model that is initoialized with a popilation of 0.

abstract type ConsumerSupplyParams{C <: FixedDecimal} <: TransactionParams end

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

function initialize_transaction_model!(model::ABM, params::FixedConsumerSupplyParams)
    reset_income_expenses!(model)
    price() = params.price
    num_consumers() = params.consumers_per_supplier
    demand() = params.demand

    add_suppliers!(params.num_suppliers, price, num_consumers, demand, model)
end

function initialize_transaction_model!(model::ABM, params::VariableConsumerSupplierParams)
    reset_income_expenses!(model)
    price() = rand(params.price)
    num_consumers() = rand(params.consumers_per_supplier)
    demand() = rand(params.demand)

    add_suppliers!(params.num_suppliers, price, num_consumers, demand, model)
end

function add_suppliers!(num_suppliers::Int, price, num_consumers, demand, model::ABM)
    for _ in 1:num_suppliers
        supplier = add_actor!(model, model.create_actor!(model))
        add_type!(supplier, :supplier)
        supplier.price = price()
        supplier.model = model

        add_consumers!(supplier, num_consumers, demand, model)
    end
end

function add_consumers!(supplier::BalanceActor, num_consumers, demand, model::ABM)
    for _ in 1:num_consumers()
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