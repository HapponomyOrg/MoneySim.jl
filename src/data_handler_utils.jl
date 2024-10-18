using EconoSim

# Actor data collectors

function equity_collector(actor)
    return liability_value(get_balance(actor), EQUITY)
end

function wealth_collector(actor)
    return max(CUR_0, liability_value(get_balance(actor), EQUITY))
end

function deposit_collector(actor)
    return asset_value(get_balance(actor), SUMSY_DEP)
end

"""
    sumsy_equity_collector(actor)

Returns the equity value of the actor at the current step.
This only produces a result that is different from the standard equity collector when SuMSy is configured to be transactional.
"""
function sumsy_equity_collector(actor)
    step = get_step(actor.model)
    g, d = calculate_adjustments(get_balance(actor), step)

    return liability_value(get_balance(actor), EQUITY) + g - d
end

"""
    sumsy_data_collector(actor)

Returns a tuple, consisting of the guaranteed income and demurrage for the current step.

    This only returns tuples that are different from (0, 0) if either SuMSy is configured to be transactional,
    or when the data is not collected at the end of a period.
"""
function sumsy_data_collector(actor)
    step = get_step(actor.model)
    return calculate_adjustments(get_balance(actor), step)
end

function sumsy_wealth_collector(actor)
    return max(CUR_0, sumsy_equity_collector(actor))
end

function sumsy_deposit_collector(actor)
    return sumsy_assets(actor, get_step(actor.model))
end

# Model data collectors

function gdp_collector!(model::ABM)
    gdp = model.gdp
    model.gdp = CUR_0

    return gdp
end

function transactions_collector!(model::ABM)
    transactions = model.transactions
    model.transactions = 0

    return transactions
end

function min_transaction_collector!(model::ABM)
    min_transaction = model.min_transaction
    model.min_transaction = typemax(Currency)

    return min_transaction
end

function max_transaction_collector!(model::ABM)
    max_transaction = model.max_transaction
    model.max_transaction = typemin(Currency)

    return max_transaction
end

function sumsy_data_collector!(model::ABM)
    gi = model.total_gi
    demurrage = model.total_demurrage
    model.total_gi = CUR_0
    model.total_demurrage = CUR_0

    return (gi, demurrage, gi - demurrage)
end

function non_broke_actors(model::ABM)
    non_broke = 0

    for actor in allagents(model)
        if !is_broke(actor)
            non_broke += 1
        end
    end

    return non_broke
end

# No data handler

NO_DATA_HANDLER = NoDataHandler()

# Full data handler

function full_post_processing!(actor_data, model_data)
    rename!(actor_data, 3 => :deposit_data, 4 => :equity_data, 5 => :wealth_data)
    rename!(model_data, 2 => :num_actors, 3 => :non_broke_actors)

    return actor_data, model_data
end

full_data_handler(interval::Int) = IntervalDataHandler(interval = interval,
                                                        actor_data_collectors = [equity_collector,
                                                            wealth_collector,
                                                            deposit_collector,
                                                            :types],
                                                        model_data_collectors = [nagents, non_broke_actors],
                                                        post_processing! = full_post_processing!)

# Full SuMSy data handler

function full_sumsy_post_processing!(actor_data, model_data)
    rename!(actor_data, 3 => :deposit_data, 4 => :equity_data, 5 => :wealth_data)
    rename!(model_data, 2 => :num_actors)
    
    sumsy_data = model_data[!, :sumsy_data_collector!]
    gi = Vector{Currency}(undef, length(sumsy_data))
    dem = Vector{Currency}(undef, length(sumsy_data))
    n_gi = Vector{Currency}(undef, length(sumsy_data))
    
    for i in eachindex(sumsy_data)
        gi[i] = sum(sumsy_data[i][1])
        dem[i] = sum(sumsy_data[i][2])
        n_gi[i] = sum(sumsy_data[i][3])
    end

    model_data = model_data[:, Not([:sumsy_data_collector!])]
    model_data[!, :guaranteed_income] = gi
    model_data[!, :demurrage] = dem
    model_data[!, :net_guaranteed_income] = n_gi

    return actor_data, model_data
end

full_sumsy_data_handler(interval::Int) = IntervalDataHandler(interval = interval,
                                                                actor_data_collectors = [equity_collector,
                                                                                        wealth_collector,
                                                                                        deposit_collector,
                                                                                        :types],
                                                                model_data_collectors = [nagents,
                                                                                        sumsy_data_collector!],
                                                                post_processing! = full_sumsy_post_processing!)

# Money stock data handler

function money_stock_post_processing!(actor_data, model_data)
    rename!(actor_data, 3 => :deposit_data)
    rename!(model_data, 2 => :num_actors)

    return actor_data, model_data
end

money_stock_data_handler(interval::Int) = IntervalDataHandler(interval = interval,
                                                                actor_data_collectors = [deposit_collector],
                                                                model_data_collectors = [nagents],
                                                                post_processing! = money_stock_post_processing!)

# GDP data handler

function gdp_post_processing!(actor_data, model_data)
    actor_data, model_data = full_post_processing!(actor_data, model_data)
    rename!(model_data,
            3 => :non_broke_actors,
            4 => :gdp,
            5 => :transactions,
            6 => :min_transaction,
            7 => :max_transaction)

    return actor_data, model_data
end

gdp_data_handler(interval::Int = 1) = IntervalDataHandler(interval = interval,
                                                        actor_data_collectors = [equity_collector,
                                                                                wealth_collector,
                                                                                deposit_collector,
                                                                                :types],
                                                        model_data_collectors = [nagents,
                                                                                non_broke_actors,
                                                                                gdp_collector!,
                                                                                transactions_collector!,
                                                                                min_transaction_collector!,
                                                                                max_transaction_collector!],
                                                        post_processing! = gdp_post_processing!)