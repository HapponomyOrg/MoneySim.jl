using EconoSim
using StatsPlots
using Random
using Agents
using DataFrames

# include("SumSySimulation.jl")

NUM_ACTORS = 1000

BOTTOM_0_1 = 1:Int64(round(NUM_ACTORS / 1000))
BOTTOM_1 = 1:Int64(NUM_ACTORS / 100)
BOTTOM_10 = 1:Int64(NUM_ACTORS / 10)
BOTTOM_50 = 1:Int64(NUM_ACTORS / 2)
MIDDLE_40 = Int64(NUM_ACTORS / 2 + 1):Int64(NUM_ACTORS - NUM_ACTORS / 10)
TOP_10 = Int64(NUM_ACTORS - NUM_ACTORS / 10 + 1):NUM_ACTORS
TOP_1 = Int64(NUM_ACTORS - NUM_ACTORS / 100 + 1):NUM_ACTORS
TOP_0_1 = Int64(round(NUM_ACTORS + 1 - NUM_ACTORS / 1000)):NUM_ACTORS
PERCENTILES = [BOTTOM_0_1, BOTTOM_1, BOTTOM_10, BOTTOM_50, MIDDLE_40, TOP_10, TOP_1, TOP_0_1]

function run_standard_yard_sale_simulation(sumsy_base::SuMSy = BASIC_SUMSY;
                                            num_actors::Integer = NUM_ACTORS,
                                            num_transactions::Integer = NUM_TRANSACTIONS,
                                            sim_length::Integer = SIM_LENGTH,
                                            concentrated::Bool = false)
    set_random_seed()
    start_balance = telo(sumsy_base) == CUR_MAX ? telo(BASIC_SUMSY) : telo(sumsy_base)
    model = create_econo_model()
    model.properties[:num_transactions] = num_transactions
    model.properties[:last_transaction] = model.step

    add_actors!(model, num_actors, start_balance,
                concentrated = concentrated,
                activate_sumsy = false)

    add_model_behavior!(model, yard_sale!)

    data, _ = run_econo_model!(model, sim_length * sumsy_base.interval, adata = [deposit_data, equity_data, wealth_data])

    return data
end

function run_debt_based_simulation(sumsy_base::SuMSy = BASIC_SUMSY;
                                    transaction_model::Function = yard_sale!,
                                    model_action::Function = nothing,
                                    active_sumsy = NO_SUMSY,
                                    num_actors::Integer = NUM_ACTORS,
                                    num_transactions::Integer = NUM_TRANSACTIONS,
                                    sim_length::Integer = SIM_LENGTH,
                                    concentrated::Bool = false)
    set_random_seed()
    model = create_econo_model()
    model.properties[:sumsy_base] = sumsy_base
    model.properties[:bank] = Balance()    
    start_balance = telo(sumsy_base)
    model.properties[:num_transactions] = num_transactions
    model.properties[:last_transaction] = model.step

    add_actors!(model, num_actors, start_balance,
                concentrated = concentrated,
                activate_sumsy = false)

    for actor in allagents(model)
        actor.debts = []
    end

    add_model_behavior!(model, transaction_model)

    if model_action !== nothing
        add_model_behavior!(model, model_action)
    end

    data, _ = run_econo_model!(model, sim_length, adata = [deposit_data, equity_data, wealth_data])

    return data
end

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



# df = run_debt_based_simulation(model_action = borrow_income, num_actors = 1000, num_transactions = 10, sim_length = 10)
# dfa = analyse_money_stock(df)
# plot_money_stock(dfa, "Borrow net income")