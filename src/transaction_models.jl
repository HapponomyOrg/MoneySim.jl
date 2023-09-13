using Agents
using FixedPointDecimals

abstract type TransactionParams{C <: FixedDecimal} end

# Yard sale model
struct YardSaleParams{C <: FixedDecimal} <: TransactionParams{C}
    wealth_transfer_range::StepRange{Percentage, Percentage}
    minimal_wealth_transfer::C
    YardSaleParams(wealth_transfer_range,
                    minimal_wealth_transfer::Real) = new{Currency}(wealth_transfer_range,
                                                                    minimal_wealth_transfer)
end

function yard_sale!(model::ABM)
    transactions = rand(model.transaction_range)

    for i in 1:transactions
        atomic_yard_sale!(model)
    end
end

#Taxed yard sale model
struct TaxedYardSaleParams{C <: FixedDecimal} <: TransactionParams{C}
    wealth_transfer_range::UnitRange{Int}
    minimal_wealth_transfer::C
    tax::Percentage
end

function taxed_yard_sale!(model::ABM)
    transactions = rand(model.transaction_range)
    tax = model.transaction_params.tax

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
    transfer_rate = rand(model.transaction_params.wealth_transfer_range)
    b1 = get_balance(target1)
    b2 = get_balance(target2)

    if b1 isa SuMSyBalance && is_transactional(b1)
        adjust_sumsy_balance!(b1, model.step)
    end

    if b2 isa SuMSyBalance && is_transactional(b2)
        adjust_sumsy_balance!(b2, model.step)
    end

    av1 = max(CUR_0, asset_value(target1.balance, SUMSY_DEP))
    av2 = max(CUR_0, asset_value(target2.balance, SUMSY_DEP))

    source, destination, amount = randomize_direction(target1,
                                                        av1,
                                                        target2,
                                                        av2,
                                                        transfer_rate)
    
    return source, destination, max(amount, model.transaction_params.minimal_wealth_transfer)
end

function randomize_direction(target1::AbstractActor,
                            av1::Real,
                            target2::AbstractActor,
                            av2::Real,
                            transfer_rate::Real)
    transfer = max(CUR_0,
            Currency(min(av1, av2) * transfer_rate))

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

struct ConsumerSupplierParams{C <: FixedDecimal} <: TransactionParams{C}
end