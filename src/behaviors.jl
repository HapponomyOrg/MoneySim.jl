using EconoSim
using StatsPlots
using Random
using Agents
using DataFrames

# Borrowing behaviours for a debt-based model. They expect model properties `sumsy_base` (a SuMSy),
# `sumsy_interval` (its period) and `bank` (the bank's Balance), and a `debts` vector on every actor.
# They act once per SuMSy period.

period_start(model) = mod(get_step(model), model.sumsy_interval) == 0

function settle_debts!(actor)
    settled_debts = []

    for debt in actor.debts
        process_debt!(debt)

        if debt_settled(debt)
            push!(settled_debts, debt)
        end
    end

    for debt in settled_debts
        delete_element!(actor.debts, debt)
    end
end

function borrow_income(model)
    sumsy = model.sumsy_base
    step = get_step(model)
    interval = model.sumsy_interval

    if period_start(model)
        for actor in allagents(model)
            settle_debts!(actor)

            income, demurrage = calculate_timerange_adjustments(asset_value(actor.balance, SUMSY_DEP), sumsy, true, sumsy.demurrage.dem_free, interval, interval, false)
            income = max(0, income - demurrage)

            if (income > 0)
                push!(actor.debts, bank_loan(model.bank, actor.balance, income, 0, 20, interval, step, money_entry = SUMSY_DEP))
            end
        end
    end
end

function borrow_when_poor(model)
    sumsy = model.sumsy_base
    step = get_step(model)
    interval = model.sumsy_interval

    if period_start(model)
        for actor in allagents(model)
            settle_debts!(actor)

            if (asset_value(actor.balance, SUMSY_DEP) < 100)
                push!(actor.debts, bank_loan(model.bank, actor.balance, 1000, 0, 20, interval, step, money_entry = SUMSY_DEP))
            end
        end
    end
end

function borrow_when_rich(model)
    sumsy = model.sumsy_base
    step = get_step(model)
    interval = model.sumsy_interval

    if period_start(model)
        for actor in allagents(model)
            settle_debts!(actor)

            balance_value = asset_value(actor.balance, SUMSY_DEP)

            if (balance_value > 50000)
                push!(actor.debts, bank_loan(model.bank, actor.balance, balance_value / 10, 0, 20, interval, step, money_entry = SUMSY_DEP))
            end
        end
    end
end

function ubi_borrow_when_poor(model)
    sumsy = model.sumsy_base
    step = get_step(model)
    interval = model.sumsy_interval

    if period_start(model)
        for actor in allagents(model)
            book_asset!(get_balance(actor), SUMSY_DEP, sumsy.income.guaranteed_income)
        end
    end

    borrow_when_poor(model)
end

function ubi_borrow_when_poor_rich(model)
    sumsy = model.sumsy_base
    step = get_step(model)
    interval = model.sumsy_interval

    if period_start(model)
        for actor in allagents(model)
            book_asset!(get_balance(actor), SUMSY_DEP, sumsy.income.guaranteed_income)
        end
    end

    borrow_when_poor(model)
    borrow_when_rich(model)
end