using EconoSim
using StatsPlots
using Random
using Agents
using DataFrames

#include("SumSySimulation.jl")

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

    add_actors!(model, num_actors, start_balance,
                concentrated = concentrated,
                activate_sumsy = false)

    add_model_behavior!(model, yard_sale!)

    data, _ = run_econo_model!(model, sim_length * sumsy_base.interval, adata = [deposit_data, equity_data])

    return data
end

function deposit_net_income(model, actor)
    last_transaction = isnothing(actor.last_transaction) ? 1 : actor.last_transaction
    interval = model.step - last_transaction
    d = calculate_demurrage(sumsy_balance(actor,  model), model.sumsy) * interval / model.sumsy.interval
    gi = model.sumsy.guaranteed_income * interval / model.sumsy.interval
    book_asset!(actor.balance, model.sumsy.dep_entry, gi - d)
    actor.last_transaction = model.step
end

function sumsy_yard_sale!(model)
    target1 = random_agent(model)
    target2 = random_agent(model)

    for i in 1:model.num_transactions
        deposit_net_income(model, target1)
        deposit_net_income(model, target2)
        yard_sale_transfer!(target1, target2, model)
    end
end

function run_transaction_based_sumsy_simulation(sumsy_base::SuMSy = BASIC_SUMSY;
                                                num_actors::Integer = NUM_ACTORS,
                                                num_transactions::Integer = NUM_TRANSACTIONS,
                                                sim_length::Integer = SIM_LENGTH,
                                                concentrated::Bool = false)
    set_random_seed()
    start_balance = telo(sumsy_base) == CUR_MAX ? telo(BASIC_SUMSY) : telo(sumsy_base)
    model = create_econo_model()
    model.properties[:sumsy] = sumsy_base
    model.properties[:num_transactions] = num_transactions

    add_actors!(model, num_actors, start_balance, SUMSY_DEP, concentrated = concentrated)
    add_model_behavior!(model, sumsy_yard_sale!)

    data, _ = run_econo_model!(model, sim_length * sumsy_base.interval, adata = [deposit_data, equity_data])

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

            income = max(0, sumsy.guaranteed_income - calculate_demurrage(actor.balance, sumsy, step))

            if (income > 0)
                push!(actor.debts, bank_loan(model.bank, actor.balance, income, 0, 20, sumsy.interval, step, money_entry = SUMSY_DEP))
            end
        end
    end
end

function run_debt_based_simulation(sumsy_base::SuMSy = BASIC_SUMSY;
                                    active_sumsy = NO_SUMSY,
                                    num_actors::Integer = NUM_ACTORS,
                                    num_transactions::Integer = NUM_TRANSACTIONS,
                                    sim_length::Integer = SIM_LENGTH,
                                    concentrated::Bool = false)
    set_random_seed()
    model = create_sumsy_model(active_sumsy, borrow_income)
    model.properties[:sumsy_base] = sumsy_base
    model.properties[:bank] = Balance()    
    start_balance = telo(sumsy_base)
    model.properties[:num_transactions] = num_transactions

    add_actors!(model, num_actors, start_balance, SUMSY_DEP, concentrated = concentrated)

    for actor in allagents(model)
        actor.debts = []
    end

    add_model_behavior!(model, yard_sale!)

    data, _ = run_econo_model!(model, sim_length, adata = [deposit_data, equity_data])

    return data
end

function analyse_wealth(data)
    # deleteat!(data, 1:NUM_ACTORS)
    groups = groupby(data, :step)

    # Create data frame
    analysis = DataFrame(cycle = Int64[],
                        money_stock = Fixed(4)[],
                        total_wealth = Fixed(4)[],
                        bottom_0_1 = Fixed(4)[],
                        bottom_1 = Fixed(4)[],
                        bottom_10 = Fixed(4)[],
                        bottom_50 = Fixed(4)[],
                        middle_40 = Fixed(4)[],
                        top_10 = Fixed(4)[],
                        top_1 = Fixed(4)[],
                        top_0_1 = Fixed(4)[])

    for group in groups
        total_wealth = sum(group[!, :equity_data])
        money_stock = sum(group[!, :deposit_data])
        rows = eachrow(sort(group, :equity_data))
        wealth_values = zeros(Fixed(4), 1, 8)
        wealth_percentages = zeros(Fixed(4), 1, 8)

        for index in 1:length(PERCENTILES)
            for i in PERCENTILES[index]
                wealth_values[index] += rows[i][:equity_data]
            end

            wealth_percentages[index] = 100 * wealth_values[index] / total_wealth
        end

        push!(analysis, [[rows[1][:step]] [money_stock] [total_wealth] wealth_percentages])
    end

    return analysis
end

function plot_wealth(dataframe, title::String = "")
    @df dataframe plot([:bottom_10, :bottom_50, :middle_40, :top_10, :top_1, :top_0_1],
                        title = "Wealth distribution\n" * title,
                        label = ["Bottom 10" "Bottom 50" "Middle 40" "Top 10" "Top 1" "Top 0.1"],
                        legend = :legend)
end

function plot_outlier_wealth(dataframe, title::String)
    for i in 1:250
        deleteat!(dataframe, 1)
    end
    
    @df dataframe plot([:bottom_0_1, :bottom_1, :bottom_10, :top_10, :top_1, :top_0_1],
                        title = "Outlier wealth distribution\n" * title,
                        label = ["Bottom 0.1" "Bottom 1" "Bottom 10" "Top 10" "Top 1" "Top 0.1"],
                        ylims = [0, 100])
end