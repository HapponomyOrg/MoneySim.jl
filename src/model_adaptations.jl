using Todo

function one_time_money_injection!(model::ABM)
    if get_step(model) == 1

        for actor in allagents(model)
            sumsy = get_sumsy(actor)
            amount = telo(sumsy) == CUR_MAX ? telo(BASIC_SUMSY) : telo(sumsy)
            book_asset!(get_balance(actor), SUMSY_DEP, amount)
        end
    end
end

function constant_money_injection!(model)
    for actor in allagents(model)
        if mod(get_step(model), get_balance(actor).sumsy_interval) == 0
            amount = get_sumsy(actor).income.guaranteed_income / 2
            book_asset!(get_balance(actor), SUMSY_DEP, amount)
        end
    end
end

function one_time_money_destruction!(model)
    if get_step(model) == 1
        for actor in allagents(model)
            book_asset!(get_balance(actor), SUMSY_DEP, -sumsy_assets(actor, get_step(model)) / 2)
        end
    end
end

function constant_money_destruction!(model)
    for actor in allagents(model)
        if mod(get_step(model), get_balance(actor).sumsy_interval) == 0
            amount = -get_sumsy(actor).income.guaranteed_income / 2
            book_asset!(get_balance(actor), SUMSY_DEP, max(-sumsy_assets(actor, get_step(model)), amount))
        end
    end
end

function equal_money_distribution!(model)
    # Assume all actors have the same SuMSy interval.
    interval = get_balance(first(allagents(model))).sumsy_interval

    if mod(get_step(model), interval) == 0
        money_stock = CUR_0

        for actor in allagents(model)
            money_stock += sumsy_assets(actor, get_step(model))
        end

        new_balance = money_stock / length(allagents(model))

        for actor in allagents(model)
            book_sumsy!(get_balance(actor), new_balance, set_to_value = true)
        end
    end
end

function adjust_population!(model::ABM)
    if get_step(model) % (30 * 12) == 0 && nagents(model) != population[Int(round(get_step(model) / (30 * 12)))]
       population_adjustment = population[Int(round(get_step(model) / (30 * 12)))] - nagents(model)

       if population_adjustment > 0
           for _ in 1:population_adjustment
               agent = add_actor!(model, make_single_sumsy!(model, sumsy, MonetaryActor(model), initialize = false))
               set_last_adjustment!(agent.balance, get_step(model))
           end
       else
           for _ in 1:abs(population_adjustment)
               dead_agent = random_agent(model)
               heir = random_agent(model)

               while dead_agent == heir
                   heir = random_agent(model)
               end

               transfer_sumsy!(model, dead_agent, heir, asset_value(get_balance(dead_agent), SUMSY_DEP))

               remove_agent!(dead_agent, model)
           end
       end

    end
end