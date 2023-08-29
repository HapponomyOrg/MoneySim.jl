abstract type TransactionParams end

# Yard sale model
struct YardSaleParams <: TransactionParams
    wealth_transfer_range::UnitRange{Int}
    minimal_wealth_transfer::Currency
end

function yard_sale!(model::ABM)
    transactions = rand(model.transaction_range)

    for i in 1:transactions
        atomic_yard_sale!(model)
    end
end

#Taxed yard sale model
struct TaxedYardSaleParams <: TransactionParams
    wealth_transfer_range::UnitRange{Int}
    minimal_wealth_transfer::Currency
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
    target1 = random_actor(model)
    target2 = random_actor(model)
    source, destination, amount = yard_sale_transfer(target1, target2, model)
    transfer_asset!(source, destination, SUMSY_DEP, amount)

    return source, destination, amount
end

function yard_sale_transfer(target1::AbstractActor,
                                target2::AbstractActor,
                                model::ABM)
    transfer_rate = rand(model.transaction_params.wealth_transfer_range)

    if get_balance(target1) isa SuMSyBalance
        av1 = max(CUR_0, sumsy_assets(target1, model.step))
    else
        av1 = max(CUR_0, asset_value(target1.balance, SUMSY_DEP))
    end

    if get_balance(target2) isa SuMSyBalance
        av2 = max(CUR_0, sumsy_assets(target2, model.step))
    else
        av2 = max(CUR_0, asset_value(target2.balance, SUMSY_DEP))
    end

    source, destination, amount = randomize_direction(target1,
                                                        av1,
                                                        target2,
                                                        av2,
                                                        transfer_rate)
    
    return source, destination, min(amount, model.transaction_params.minimal_wealth_transfer)
end

function randomize_direction(target1::AbstractActor,
                            av1::Currency,
                            target2::AbstractActor,
                            av2::Currency,
                            transfer_rate::Real)
    transfer = max(C_0,
            Currency(min(av1, av2) * transfer_rate))

    if rand(1:2) == 1
        source = get_balance(target1)
        destination = get_balance(target2)
        avs = av1
        avd = av2
    else
        source = get_balance(target2)
        destination = get_balance(target1)
        avs = av2
        avd = av1
    end

    return source, destination, transfer
end

# Consumer/Supplier model

struct ConsumerSupplierParams <: TransactionParams
end