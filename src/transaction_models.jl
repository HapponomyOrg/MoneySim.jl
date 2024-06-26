using Agents
using FixedPointDecimals
using EconoSim

abstract type TransactionParams{C <: FixedDecimal} end

function adjusted_asset_value!(actor::BalanceActor)
    balance = get_balance(actor)

    if balance isa SuMSyBalance && is_transactional(balance)
        adjust_sumsy_balance!(balance, actor.model.step)
    end

    return asset_value(balance, SUMSY_DEP)
end

# No Transaction Model

struct NoTransactionParams <: TransactionParams{Currency}
    num_actors::Int
    NoTransactionParams(num_actors::Int) = new(num_actors)
end

function initialize_transaction_model!(model::ABM,
                                       no_transaction_params::NoTransactionParams)
    
    for _ in 1:no_transaction_params.num_actors
        add_actor!(model, model.create_actor!(model))
    end
    
    return model
end

# Yard sale model
abstract type YardSaleParams{C <: FixedDecimal} <: TransactionParams{C} end

struct StandardYardSaleParams{C <: FixedDecimal} <: YardSaleParams{C}
    num_actors::Int
    transaction_range::UnitRange{Int}
    wealth_transfer_range::StepRange{Percentage, Percentage}
    minimal_wealth_transfer::C
    StandardYardSaleParams(num_actors::Int,
                            transfer_range::UnitRange{Int},
                            wealth_transfer_range::Union{StepRange, StepRangeLen},
                            minimal_wealth_transfer::Real) = new{Currency}(num_actors,
                                                                            transfer_range,
                                                                            wealth_transfer_range,
                                                                            minimal_wealth_transfer)
end

struct TaxedYardSaleParams{C <: FixedDecimal} <: YardSaleParams{C}
    num_actors::Int
    transaction_range::UnitRange{Int}
    wealth_transfer_range::StepRange{Percentage, Percentage}
    minimal_wealth_transfer::C
    tax::Percentage
    TaxedYardSaleParams(num_actors::Int,
                        transfer_range::UnitRange{Int},
                        wealth_transfer_range::Union{StepRange, StepRangeLen},
                        minimal_wealth_transfer::Real,
                        tax::Real) = new{Currency}(num_actors,
                                                    transfer_range,
                                                    wealth_transfer_range,
                                                    minimal_wealth_transfer,
                                                    tax)
end

struct GDPYardSaleParams{C <: FixedDecimal} <: YardSaleParams{C}
    population::Int
    gdp::C
    gdp_period::Int
    wealth_transfer_range::StepRange{Percentage, Percentage}
    minimal_wealth_transfer::C
    gdp_model_behavior::Function
    GDPYardSaleParams(population::Int,
                        gdp::Real,
                        gdp_period::Int,
                        wealth_transfer_range::Union{StepRange, StepRangeLen},
                        minimal_wealth_transfer::Real,
                        gdp_model_behavior) = new{Currency}(population,
                                                                        gdp,
                                                                        gdp_period,
                                                                        wealth_transfer_range,
                                                                        minimal_wealth_transfer,
                                                                        gdp_model_behavior)
end

function initialize_transaction_model!(model::ABM, params::StandardYardSaleParams)
    initialize_yard_sale!(model, params)
    add_model_behavior!(model, yard_sale!)
end

function initialize_transaction_model!(model::ABM, params::TaxedYardSaleParams)
    initialize_yard_sale!(model, params)
    abmproperties(model)[:tax] = params.tax
    add_model_behavior!(model, taxed_yard_sale!)
end

function initialize_transaction_model!(model::ABM, params::GDPYardSaleParams)
    properties = abmproperties(model)

    properties[:min_gdp_per_cycle] = params.gdp / params.gdp_period
    properties[:wealth_transfer_range] = params.wealth_transfer_range
    properties[:minimal_wealth_transfer] = params.minimal_wealth_transfer
    properties[:gdp_period] = params.gdp_period
    properties[:gdp] = params.gdp
    properties[:transactions] = 0

    for i in 1:params.population
        add_actor!(model, model.create_actor!(model))
    end

    add_model_behavior!(model, params.gdp_model_behavior)
end

function initialize_yard_sale!(model::ABM, params::YardSaleParams)
    properties = abmproperties(model)

    properties[:transaction_range] = params.transaction_range
    properties[:wealth_transfer_range] = params.wealth_transfer_range
    properties[:minimal_wealth_transfer] = params.minimal_wealth_transfer

    for i in 1:params.num_actors
        add_actor!(model, model.create_actor!(model))
    end
end

function yard_sale!(model::ABM)
    transactions = rand(model.transaction_range)

    for i in 1:transactions
        atomic_yard_sale!(model)
    end
end

function taxed_yard_sale!(model::ABM)
    transactions = rand(model.transaction_range)
    tax = model.tax

    for i in 1:transactions
        _, destination, amount = atomic_yard_sale!(model)
        book_asset!(destination, SUMSY_DEP, -amount * tax)
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
    cycle_gdp = 0
    transactions = 0

    while cycle_gdp < model.min_gdp_per_cycle
        _, _, amount = atomic_yard_sale!(model)
        cycle_gdp += amount
        transactions += 1
    end    

    if model.step % model.gdp_period == 0
        model.gdp = cycle_gdp
        model.transactions = transactions

        abmproperties(model)[:max_transactions] = max(model.max_transactions, 10 * transactions)
        delete_model_behavior!(model, gdp_baseline_yard_sale!)
        add_model_behavior!(model, gdp_constrained_yard_sale!)
    else
        model.gdp += cycle_gdp
        model.transactions += transactions
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
    cycle_gdp = 0
    transactions = 0

    while cycle_gdp < model.min_gdp_per_cycle && transactions < model.max_transactions
        _, _, amount = atomic_yard_sale!(model)
        cycle_gdp += amount
        transactions += 1
    end

    if model.step % model.gdp_period == 1
        model.gdp = cycle_gdp
        model.transactions = transactions
    else
        model.gdp += cycle_gdp
        model.transactions += transactions
    end
end

"""
    gdp_yard_sale!!(model::ABM)

    Executes the yard sale model for each period, making sure that GDP is reached over each period.
"""
function gdp_yard_sale!(model::ABM)
    cycle_gdp = 0
    transactions = 0

    while cycle_gdp < model.min_gdp_per_cycle
        _, _, amount = atomic_yard_sale!(model)
        cycle_gdp += amount
        transactions += 1
    end

    if model.step % model.gdp_period == 1
        model.gdp = cycle_gdp
        model.transactions = transactions
    else
        model.gdp += cycle_gdp
        model.transactions += transactions
    end
end

function atomic_yard_sale!(model::ABM)
    target1 = random_agent(model)
    target2 = random_agent(model)
    source, destination, amount = yard_sale_transfer!(target1, target2, model)
    
    transfer_asset!(source, destination, SUMSY_DEP, amount, timestamp = model.step)

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
        source = get_balance(target1)
        destination = get_balance(target2)
    else
        source = get_balance(target2)
        destination = get_balance(target1)
    end

    return source, destination, transfer
end

# Consumer/Supplier model

abstract type ConsumerSupplyParams{C <: FixedDecimal} <: TransactionParams{C} end

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
    price() = params.price
    num_consumers() = params.consumers_per_supplier
    demand() = params.demand

    add_suppliers!(params.num_suppliers, price, num_consumers, demand, model)
end

function initialize_transaction_model!(model::ABM, params::VariableConsumerSupplierParams)
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