using Agents
using FixedPointDecimals
using EconoSim
using Random
# Temp code
#  using DataFrames
#  using CSV
# End temp code

function adjusted_asset_value!(actor::AbstractBalanceActor)
    balance = get_balance(actor)

    if balance isa SuMSyBalance && is_transactional(balance)
        adjust_sumsy_balance!(balance, get_step(actor.model))
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

    * execute_transaction! - The function that executes the transactions.
                                It must accept a model as a parameter.
"""
struct BareBonesParams{F} <: TransactionParams
    execute_transaction!::F
    BareBonesParams(execute_transaction!) = new{typeof(execute_transaction!)}(execute_transaction!)
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

"""
    struct StandardYardSaleParams{C <: FixedDecimal, DF, AF, AW} <: YardSaleParams
        transaction_range::UnitRange{Int}
        wealth_transfer_range::StepRange{Percentage, Percentage}
        minimal_wealth_transfer::C
        determine_direction::DF
        adjust_income!::AF
        wealth_accumulation_advantage::Float64
        average_wealth::AW
    end
    
    * transaction_range: 
    * wealth_transfer_range: 
    * minimal_wealth_transfer: 
    * determine_direction: Determines the direction of the wealth transfer. This function needs to have a method signature:
        (actor_1::AbstractActor,
        wealth_actor_1::C,
        actor_2::AbstractActor,
        wealth_actor_2::C,
        wealth_advantage::Number,
        average_wealth::AW
    * adjust_income: 
    * wealth_advantage: the wealth advantage adjustment. Must be between -1 and 1, edges included.
    * average_wealth: either a number or a function that takes a model as its single parameter.
"""
struct StandardYardSaleParams{C <: FixedDecimal, DF, AF, AW} <: YardSaleParams
    transaction_range::UnitRange{Int}
    wealth_transfer_range::StepRange{Percentage, Percentage}
    minimal_wealth_transfer::C
    determine_direction::DF
    adjust_income!::AF # A Function or nothing
    wealth_accumulation_advantage::Float64
    average_wealth::AW # A Function or C
    StandardYardSaleParams(;transaction_range::UnitRange{Int},
                            wealth_transfer_range::Union{StepRange, StepRangeLen},
                            minimal_wealth_transfer::Real = 0,
                            determine_direction::Function = coinflip,
                            adjust_income! = nothing,
                            wealth_accumulation_advantage::Real = 0,
                            average_wealth::Union{Real, Function}) = new{Currency,
                                                                        typeof(determine_direction),
                                                                        typeof(adjust_income!),
                                                                        typeof(average_wealth)}(
                                                                        transaction_range,
                                                                        wealth_transfer_range,
                                                                        minimal_wealth_transfer,
                                                                        determine_direction,
                                                                        adjust_income!,
                                                                        wealth_accumulation_advantage,
                                                                        average_wealth)
end

"""
struct GDPYardSaleParams{C <: FixedDecimal} <: YardSaleParams{C}
    * gdp_period::Int - The number of cycles per GDP period.
    * gdp_per_capita::C - The GDP per actor over a period.
    * wealth_transfer_range::StepRange{Percentage, Percentage} - The range of percentage values to be used in the wealth transfer.
    * minimal_wealth_transfer::C - The minimal amount of wealth that needs to be transferred.
    * yard_sale! - The function that determines the direction and amount of each transaction, based on the other parameters.
"""
struct GDPYardSaleParams{C <: FixedDecimal, GF, DF, AF, AW} <: YardSaleParams
    gdp_period::Int
    gdp_per_capita::C
    gdp_growth::GF
    wealth_transfer_range::StepRange{Percentage, Percentage}
    minimal_wealth_transfer::C
    determine_direction::DF
    adjust_income!::AF # A Function or nothing
    wealth_accumulation_advantage::Float64
    average_wealth::AW # A Function or C
    GDPYardSaleParams(;gdp_period::Int,
                        gdp_per_capita::Real,
                        gdp_growth::Function = 0,
                        wealth_transfer_range::Union{StepRange, StepRangeLen},
                        minimal_wealth_transfer::Real,
                        determine_direction::Function = coinflip,
                        adjust_income!::Union{Nothing, Function} = nothing,
                        wealth_accumulation_advantage::Real = 0,
                        average_wealth::Union{Real, Function}) = new{Currency,
                                                                    typeof(gdp_growth),
                                                                    typeof(determine_direction),
                                                                    typeof(adjust_income!),
                                                                    typeof(average_wealth)}(
                                                                    gdp_period,
                                                                    gdp_per_capita,
                                                                    gdp_growth,
                                                                    wealth_transfer_range,
                                                                    minimal_wealth_transfer,
                                                                    determine_direction,
                                                                    adjust_income!,
                                                                    wealth_accumulation_advantage,
                                                                    average_wealth)
end

"""
struct GDPTypedYardSaleParams{C <: FixedDecimal} <: YardSaleParams{C}
    * gdp_period::Int - The number of cycles per GDP period.
    * gdp_per_capita::C - The GDP per actor over a period.
    * gdp_growth::Function - A function that takes a model and the GDP period as parameters and returns a growth rate for that period.
    * wealth_transfer_range::Dict{Symbol, StepRange{Percentage, Percentage}} - The range of percentage values to be used in the wealth transfer.
    * income_probabliity::Dict{Symbol, Real} - The probability of income for each actor type.
    * determine_direction::Function - The function that determines the direction of the transaction.
    * adjust_income!::Function - A function or nothing that adjusts the income of the actors before transactions are executed.
    * wealth_acumulation_advantage::Real - A number between 0 and 1 that represents wealth accumulation advantage.
    * average_wealth::Union{Real, Function} - A number or function 
"""
struct GDPTypedYardSaleParams{C <: FixedDecimal, GF, DF, AF, AW} <: YardSaleParams
    gdp_period::Int
    gdp_per_capita::C
    gdp_growth::GF
    wealth_transfer_range::Dict{Symbol, StepRange{Percentage, Percentage}}
    income_probabliity::Dict{Symbol, Real}
    determine_direction::DF
    adjust_income!::AF # A Function or nothing
    wealth_accumulation_advantage::Float64
    average_wealth::AW # A Function or C
    GDPTypedYardSaleParams(;gdp_period::Int,
                            gdp_per_capita::Real,
                            gdp_growth::Function,
                            wealth_transfer_range::Dict{Symbol, Union{StepRange, StepRangeLen}},
                            income_probabliity::Dict{Symbol, Real},
                            determine_direction::Function = coinflip,
                            adjust_income!::Union{Nothing, Function} = nothing,
                            wealth_accumulation_advantage::Real = 0,
                            average_wealth::Union{Real, Function}) = new{Currency,
                                                                    typeof(gdp_growth),
                                                                    typeof(determine_direction),
                                                                    typeof(adjust_income!),
                                                                    typeof(average_wealth)}(
                                                                    gdp_period,
                                                                    gdp_per_capita,
                                                                    gdp_growth,
                                                                    wealth_transfer_range,
                                                                    income_probabliity,
                                                                    determine_direction,
                                                                    adjust_income!,
                                                                    wealth_accumulation_advantage,
                                                                    average_wealth)
end

function initialize_transaction_model!(model::ABM, params::StandardYardSaleParams)
    initialize_yard_sale!(model, params)
    properties = abmproperties(model)

    properties[:transaction_range] = params.transaction_range
    
    add_model_behavior!(model,
                        x -> yard_sale!(x, params.determine_direction, params.adjust_income!))
end

function add_gdp_properties!(model::ABM, params::YardSaleParams)
    initialize_yard_sale!(model, params)
    properties = abmproperties(model)

    properties[:gdp] = params.gdp_per_capita * nagents(model)
    properties[:data_gdp] = params.gdp_per_capita * nagents(model)
    properties[:gdp_period] = params.gdp_period
    properties[:current_gdp_cycle] = 1
    properties[:min_gdp_per_cycle] = model.data_gdp / model.gdp_period
    properties[:max_gdp] = CUR_0
    properties[:gdp_growth] = params.gdp_growth
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

    properties[:data_transactions] = 0
    properties[:wealth_transfer_range] = params.wealth_transfer_range
    properties[:minimal_wealth_transfer] = params.minimal_wealth_transfer
    properties[:waa] = params.wealth_accumulation_advantage
    properties[:avg_wealth] = params.average_wealth

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
        i += 1
    end
end

function yard_sale!(model::ABM,
                    determine_direction::Function,
                    adjust_income!)
    reset_income_expenses!(model)

    if !isnothing(adjust_income!)
        adjust_income!(model)
    end

    transactions = rand(model.transaction_range)
    non_broke_actor_ids = collect(allids(model))

    for _ in 1:transactions
        if length(non_broke_actor_ids) > 1
            atomic_yard_sale!(model, determine_direction, non_broke_actor_ids)
        else
            break
        end
    end

    model.data_transactions += transactions
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
                        adjust_income!)
    reset_income_expenses!(model)

    gdp = model.gdp
    transactions = 0
    avg_wealth = model.avg_wealth(model)

    if !isnothing(adjust_income!)
        adjust_income!(model)

        # This can raise this cycle's GDP above the limit of model.min_gdp_per_cycle.
        for actor in allagents(model)
            income = actor.income
            gdp += income

            if income > 0
                transactions += 1
            end
        end
    end

    amount = 0
    min_transaction = model.data_min_transaction
    max_transaction = model.data_max_transaction
    max_gdp = model.max_gdp + model.min_gdp_per_cycle
    non_broke_actor_ids = collect(allids(model))

    while gdp < max_gdp && length(non_broke_actor_ids) > 1
        _, _, amount = atomic_yard_sale!(model, determine_direction, non_broke_actor_ids, avg_wealth)

        if amount != 0
            transactions += 1
            gdp += amount
            min_transaction = min(min_transaction, amount)
            max_transaction = max(max_transaction, amount)
        end
    end

    model.data_transactions += transactions

    model.data_min_transaction = min_transaction
    model.data_max_transaction = max_transaction

    model.data_gdp += gdp - model.gdp

    # Set the next GDP cycle number
    if mod(model.current_gdp_cycle, model.gdp_period) == 0
        model.gdp = CUR_0
        model.current_gdp_cycle = 1
    else
        model.gdp += gdp - model.gdp
        model.current_gdp_cycle += 1
    end

    model.min_gdp_per_cycle = (1 + model.gdp_growth(model, model.gdp_period)) * model.min_gdp_per_cycle
end

function atomic_yard_sale!(model::ABM,
                            determine_direction::Function,
                            non_broke_actor_ids::Vector{Int64},
                            avg_wealth::Real)
    # Make sure two different random agents are picked.
    num_non_broke_actors = length(non_broke_actor_ids)

    target_index_1 = rand(1:num_non_broke_actors)
    target_id_1 = non_broke_actor_ids[target_index_1]
    target1 = model[target_id_1]

    target_index_2 = rand(1:num_non_broke_actors - 1)
    target_id_2 = remove_index(non_broke_actor_ids, target_index_1)[target_index_2]
    target2 = model[target_id_2]

    source, destination, amount = yard_sale_transfer(model, target1, target2, avg_wealth, determine_direction)
    
    if amount != 0
        transfer_asset!(model, source, destination, SUMSY_DEP, amount)
        add_expenses!(source, amount)
        add_income!(destination, amount)
    end

    if model.minimal_wealth_transfer == 0
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
                            avg_wealth::Real,
                            determine_direction::Function = coinflip)
    transfer_rate = rand(model.wealth_transfer_range)
    waa = model.waa

    av1 = max(CUR_0, adjusted_asset_value!(target1))
    av2 = max(CUR_0, adjusted_asset_value!(target2))

    min_balance = min(av1, av2)
    amount = max(min(min_balance, model.minimal_wealth_transfer),
            Currency(min_balance * transfer_rate))

    source, destination = determine_direction(target1, av1, target2, av2, waa, avg_wealth)
    
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
                    asset_value_2::Currency,
                    waa::Number,
                    avg_wealth::Number)
    raw_bias = waa * (asset_value_1 - asset_value_2) / avg_wealth
    bias = clamp(raw_bias, -1.0, 1.0)
    prob_1_wins = (1.0 + bias) / 2.0

    if rand() < prob_1_wins
        source = target_2
        destination = target_1
    else
        source = target_1
        destination = target_2
    end

    return source, destination
end

"""
    wealth_weighted_direction(target_1::AbstractActor,
                                asset_value_1::Currency,
                                target_2::AbstractActor,
                                asset_value_2::Currency,
                                avg_money_stock::Currency,
                                wealth_factor::Real = 1.0)
    * target_1: Actor 1
    * asset_value_1: Asset value of actor 1
    * target_2: Actor 2
    * asset_value_2: Asset value of actor 2
    * wealth_factor: Relative importance of wealth. This determines the advantage of the wealthier actor. Higher values mean higher advantage.
    * avg_money_stock: Average money stock of all actors
    * scaling_factor: Factor to use for scaling the wealth advantage.
"""
function wealth_weighted_direction(target_1::AbstractActor,
                                    asset_value_1::Currency,
                                    target_2::AbstractActor,
                                    asset_value_2::Currency;
                                    wealth_factor::Real = 1.0,
                                    avg_money_stock::Currency,
                                    scaling_factor::Real = 1.0)
    probabliity_1_to_2 = (wealth_factor * (asset_value_1 - asset_value_2) / avg_money_stock * scaling_factor) + 0.5

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
    FixedConsumerSupplyParams(;num_suppliers::Integer,
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

    connect_consumers_with_suppliers!(num_consumers, price, demand, model)
end

function connect_consumers_with_suppliers!(num_consumers, price, demand, model::ABM)
    supliers = []
    consumers = []

    for actor in allagents(model)
        if has_type(actor, :supplier)
            push!(supliers, actor)
        elseif has_type(actor, :consumer)
            push!(consumers, actor)
        end
    end

    consumer_index = 1

    for supplier in supliers
        supplier.price = price()
        supplier.model = model

        for _ in 1:num_consumers()
            consumer = consumers[consumer_index]
            consumer.supplier = supplier
            consumer.demand = demand
            consumer.model = model
            add_behavior!(consumer, satisfy_demand!)
            consumer_index += 1
        end
    end
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

function add_consumers!(supplier::AbstractBalanceActor, num_consumers, demand, model::ABM)
    for _ in 1:num_consumers()
        consumer = add_actor!(model, model.create_actor!(model))
        add_type!(consumer, :consumer)
        add_behavior!(consumer, satisfy_demand!)
        consumer.supplier = supplier
        consumer.demand = demand
    end
end

function satisfy_demand!(model::ABM, actor::AbstractBalanceActor)
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
                    timestamp = get_step(model))
end