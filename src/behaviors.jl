using EconoSim
using StatsPlots
using Random
using Agents
using DataFrames

function borrow_income(model)
    sumsy = model.sumsy_base
    step = model.step

    if process_ready(sumsy, step)
        for actor in allagents(model)
            settled_debts = []

            for debt in actor.debts
                if debt_settled(process_debt!(debt))
                    push!(settled_debts, debt)
                end
            end

            for debt in settled_debts
                delete_element!(actor.debts, debt)
            end

            income, demurrage = calculate_timerange_adjustments(asset_value(actor.balance, SUMSY_DEP), sumsy, true, sumsy.interval)
            income = max(0, income - demurrage)

            if (income > 0)
                push!(actor.debts, bank_loan(model.bank, actor.balance, income, 0, 20, sumsy.interval, step, money_entry = SUMSY_DEP))
            end
        end
    end
end

function borrow_when_poor(model)
    sumsy = model.sumsy_base
    step = model.step

    if process_ready(sumsy, step)
        for actor in allagents(model)
            settled_debts = []

            for debt in actor.debts
                if debt_settled(process_debt!(debt))
                    push!(settled_debts, debt)
                end
            end

            for debt in settled_debts
                delete_element!(actor.debts, debt)
            end

            if (asset_value(actor.balance, SUMSY_DEP) < 100)
                push!(actor.debts, bank_loan(model.bank, actor.balance, 1000, 0, 20, sumsy.interval, step, money_entry = SUMSY_DEP))
            end
        end
    end
end

function borrow_when_rich(model)
    sumsy = model.sumsy_base
    step = model.step

    if process_ready(sumsy, step)
        for actor in allagents(model)
            settled_debts = []

            for debt in actor.debts
                if debt_settled(process_debt!(debt))
                    push!(settled_debts, debt)
                end
            end

            for debt in settled_debts
                delete_element!(actor.debts, debt)
            end

            balance_value = asset_value(actor.balance, SUMSY_DEP)

            if (balance_value > 50000)
                push!(actor.debts, bank_loan(model.bank, actor.balance, balance_value / 10, 0, 20, sumsy.interval, step, money_entry = SUMSY_DEP))
            end
        end
    end
end

function ubi_borrow_when_poor(model)
    sumsy = model.sumsy_base
    step = model.step

    if process_ready(sumsy, step)
        for actor in allagents(model)
            book_asset!(get_balance(actor), SUMSY_DEP, sumsy.income.guaranteed_income)
        end
    end

    borrow_when_poor(model)
end

function ubi_borrow_when_poor_rich(model)
    sumsy = model.sumsy_base
    step = model.step

    if process_ready(sumsy, step)
        for actor in allagents(model)
            book_asset!(get_balance(actor), SUMSY_DEP, sumsy.income.guaranteed_income)
        end
    end

    borrow_when_poor(model)
    borrow_when_rich(model)
end