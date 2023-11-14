using Agents
using FixedPointDecimals
using EconoSim

abstract type TransactionParams{C <: FixedDecimal} end

function adjusted_asset_value!(actor::MonetaryActor)
    balance = get_balance(actor)

    if balance isa SuMSyBalance && is_transactional(balance)
        adjust_sumsy_balance!(balance, actor.model.step)
    end

    return asset_value(balance, SUMSY_DEP)
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
    wealth_transfer_range::UnitRange{Int}
    minimal_wealth_transfer::C
    tax::Percentage
    TaxedYardSaleParams(num_actors::Int,
                        transfer_range::UnitRange{Int},
                        wealth_transfer_range::UnitRange{Int},
                        minimal_wealth_transfer::Real,
                        tax::Real) = new{Currency}(num_actors,
                                                    transfer_range,
                                                    wealth_transfer_range,
                                                    minimal_wealth_transfer,
                                                    tax)
end

function initialize_transaction_model!(model::ABM, params::StandardYardSaleParams)
    initialize_yard_sale!(model, params)
    add_model_behavior!(model, yard_sale!)
end

function initialize_transaction_model!(model::ABM, params::TaxedYardSaleParams)
    initialize_yard_sale!(model, params)
    model.properties[:tax] = params.tax
    add_model_behavior!(model, taxed_yard_sale!)
end

function initialize_yard_sale!(model::ABM, params::YardSaleParams)
    model.properties[:transaction_range] = params.transaction_range
    model.properties[:wealth_transfer_range] = params.wealth_transfer_range
    model.properties[:minimal_wealth_transfer] = params.minimal_wealth_transfer

    for i in 1:params.num_actors
        add_actor!(model, MonetaryActor())
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

function atomic_yard_sale!(model::ABM)
    target1 = random_agent(model)
    target2 = random_agent(model)
    source, destination, amount = yard_sale_transfer(target1, target2, model)
    
    transfer_asset!(source, destination, SUMSY_DEP, amount, timestamp = model.step)

    return source, destination, amount
end

function yard_sale_transfer(target1::AbstractActor,
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
        supplier = add_actor!(model, MonetaryActor())
        add_type!(supplier, :supplier)
        supplier.price = price()
        supplier.model = model

        add_consumers!(supplier, num_consumers, demand, model)
    end
end

function add_consumers!(supplier::MonetaryActor, num_consumers, demand, model::ABM)
    for i in 1:num_consumers()
        consumer = add_actor!(model, MonetaryActor())
        add_type!(consumer, :consumer)
        add_behavior!(consumer, satisfy_demand!)
        consumer.supplier = supplier
        consumer.demand = demand
    end
end

function satisfy_demand!(model::ABM, actor::MonetaryActor)
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