function one_time_money_injection!(model)
    if model.step == 1
        amount = telo(model.sumsy) == CUR_MAX ? telo(BASIC_SUMSY) : telo(model.sumsy)

        for actor in allagents(model)
            book_asset!(get_balance(actor), SUMSY_DEP, amount)
        end
    end
end

function constant_money_injection!(model)
    amount = model.sumsy.income.guaranteed_income / 2

    if process_ready(model.sumsy, model.step)
        for actor in allagents(model)
            book_asset!(get_balance(actor), SUMSY_DEP, amount)
        end
    end
end

function one_time_money_destruction!(model)
    if model.step == 1
        for actor in allagents(model)
            book_asset!(get_balance(actor), SUMSY_DEP, -sumsy_assets(actor, model.step) / 2)
        end
    end
end

function constant_money_destruction!(model)
    amount = -model.sumsy.income.guaranteed_income / 2

    if process_ready(model.sumsy, model.step)
        for actor in allagents(model)
            book_asset!(get_balance(actor), SUMSY_DEP, max(-sumsy_assets(actor, model.step), amount))
        end
    end
end

function equal_money_distribution!(model)
    if process_ready(model.sumsy, model.step)
        money_stock = CUR_0

        for actor in allagents(model)
            money_stock += sumsy_assets(actor, model.step)
        end

        new_balance = money_stock / length(allagents(model))

        for actor in allagents(model)
            book_sumsy!(get_balance(actor), new_balance, set_to_value = true)
        end
    end
end