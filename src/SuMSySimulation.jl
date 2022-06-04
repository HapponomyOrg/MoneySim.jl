using EconoSim
using StatsPlots
using Random
using Agents
using DataFrames

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

SIM_LENGTH = 1000
NUM_TRANSACTIONS = 200

BASIC_SUMSY = SuMSy(2000, 0, 0.01, 30)
DEM_FREE_SUMSY = SuMSy(2000, 25000, 0.01, 30)
TIERED_SUMSY = SuMSy(2000, 25000, [(0, 0.01), (50000, 0.02), (500000, 0.05), (1000000, 0.1), (10000000, 0.5), (50000000, 0.95)], 30)
BROKEN_SUMSY = SuMSy(2000, 0, 0, 30)
NO_SUMSY = SuMSy(0, 0, 0, 30)
NO_GI_SUMSY = SuMSy(0, 0, 0.01, 30)

C_0_2 = Currency(0.2)
C_0 = Currency(0)
C_20 = Currency(20)

function set_random_seed()
    Random.seed!(35416816)
end

### Behaviors

function yard_sale!(model)
    for i in 1:model.num_transactions
        target1 = random_agent(model)
        target2 = random_agent(model)
        av1 = max(CUR_0, asset_value(target1.balance, SUMSY_DEP))
        av2 = max(CUR_0, asset_value(target2.balance, SUMSY_DEP))
        transfer = max(C_0,
                Currency(min(av1, av2) * C_0_2))

        if rand(1:2) == 1
            source = target1.balance
            destination = target2.balance
            avs = av1
            avd = av2
        else
            source = target2.balance
            destination = target1.balance
            avs = av2
            avd = av1
        end
        
        # Make sure a minimum amount is always transferred
        if transfer < C_20 &&
             avs > 0 &&
             avs > avd
             transfer = min(C_20, avs * C_0_2)
        end

        transfer_asset!(source, destination, SUMSY_DEP, transfer)
    end
end

function equity_data(actor)
    return equity(actor.balance)
end

function deposit_data(actor)
    return asset_value(actor.balance, SUMSY_DEP)
end

function create_actors!(model,
                        num_actors::Integer,
                        start_balance::Real,
                        entry::BalanceEntry;
                        non_gi::Bool = false,
                        non_gi_override = nothing)
    for i in 1:num_actors
        actor = Actor()
        book_asset!(actor.balance, entry, start_balance)

        if non_gi
            set_sumsy_overrides!(actor.balance, non_gi_override)
        end

        add_agent!(actor, model)
    end 
end

function add_actors!(model,
                        num_actors::Integer,
                        start_balance::Real,
                        entry::BalanceEntry;
                        add_non_gi::Bool = false,
                        non_gi_override = nothing,
                        concentrated::Bool = false)
    concentrated_balance = num_actors * start_balance
    actor_balance = concentrated ? 0 : start_balance
    actor_balance = add_non_gi ? actor_balance * num_actors / (num_actors + 0.25 * num_actors) : actor_balance

    num_gi_mod = 0
    num_non_gi_mod = 0

    if concentrated
        if add_non_gi
            create_actors!(model, 1, concentrated_balance, entry, non_gi = true, non_gi_override = non_gi_override)
            num_non_gi_mod = -1
        else
            create_actors!(model, 1, Currency(concentrated_balance), entry)
            num_gi_mod = -1
        end
    end

    create_actors!(model, num_actors + num_gi_mod, actor_balance, entry)

    if add_non_gi
        create_actors!(model, Integer(num_actors / 4) + num_non_gi_mod, actor_balance, entry, non_gi = true, non_gi_override = non_gi_override)
    end
end

function run_sumsy_simulation(sumsy::SuMSy = BASIC_SUMSY;
                                num_actors::Integer = NUM_ACTORS,
                                num_transactions::Integer = NUM_TRANSACTIONS,
                                sim_length::Integer = SIM_LENGTH,
                                add_non_gi::Bool = false,
                                concentrated::Bool = false,
                                model_adaptation::Union{Function, Nothing} = nothing)
    set_random_seed()
    start_balance = telo(sumsy) == CUR_MAX ? telo(BASIC_SUMSY) : telo(sumsy)
    model = create_sumsy_model(sumsy)
    model.properties[:num_transactions] = num_transactions

    if model_adaptation !== nothing
        add_model_behavior!(model, model_adaptation)
    end

    non_gi_override = add_non_gi ? sumsy_overrides(sumsy, guaranteed_income = 0) : nothing
    add_actors!(model, num_actors, start_balance, SUMSY_DEP, add_non_gi = add_non_gi, non_gi_override = non_gi_override, concentrated = concentrated)
    add_model_behavior!(model, yard_sale!)

    data, _ = run_econo_model!(model, sim_length * sumsy.interval , adata = [deposit_data, equity_data])

    return data
end

function one_time_money_injection!(model)
    if model.step == 1
        amount = telo(model.sumsy) == CUR_MAX ? telo(BASIC_SUMSY) : telo(model.sumsy)

        for actor in allagents(model)
            book_asset!(actor.balance, SUMSY_DEP, amount)
        end
    end
end

function constant_money_injection!(model)
    amount = model.sumsy.guaranteed_income / 2

    if process_ready(model.sumsy, model.step)
        for actor in allagents(model)
            book_asset!(actor.balance, SUMSY_DEP, amount)
        end
    end
end

function one_time_money_destruction!(model)
    if model.step == 1
        for actor in allagents(model)
            book_asset!(actor.balance, SUMSY_DEP, -sumsy_balance(actor, model) / 2)
        end
    end
end

function constant_money_destruction!(model)
    amount = -model.sumsy.guaranteed_income / 2

    if process_ready(model.sumsy, model.step)
        for actor in allagents(model)
            book_asset!(actor.balance, SUMSY_DEP, max(-sumsy_balance(actor, model), amount))
        end
    end
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

function analyse_money_stock(data)
    # deleteat!(data, 1:NUM_ACTORS)
    groups = groupby(data, :step)

    # Create data frame
    analysis = DataFrame(cycle = Int64[],
                        money_stock = Fixed(4)[],
                        total_wealth = Fixed(4)[])

    for group in groups
        rows = eachrow(group)
        total_wealth = sum(group[!, :equity_data])
        money_stock = sum(group[!, :deposit_data])

        push!(analysis, [[rows[1][:step]] [money_stock] [total_wealth]])
    end

    return analysis
end

function plot_money_stock(dataframe, title::String = ""; theoretical_min = nothing, theoretical_max = nothing)
    @df dataframe plot(:money_stock, title = "Money stock\n" * title, label = "money stock")

    if theoretical_min !== nothing
        plot!(fill(theoretical_min, size(dataframe[!, :money_stock])[1]), label = "min")
    end

    if theoretical_max !== nothing
        plot!(fill(theoretical_max, size(dataframe[!, :money_stock])[1]), label = "max")
    end
end

function plot_money_stock_per_person(dataframe, num_actors = NUM_ACTORS, title::String = "")
    plot(./(dataframe[!, :money_stock], num_actors), title = "Money stock\n" * title, label = "Money stock")
end

function time_telo(sumsy::SuMSy, balance::Balance = Balance())
    t = 0
    eq = telo(sumsy)

    while asset_value(balance, SUMSY_DEP) < eq - 1
        dem = calculate_demurrage(balance, sumsy, 0)
        book_asset!(balance, SUMSY_DEP, sumsy.guaranteed_income - dem)
        t += 1
    end

    return t
end

function plot_balance(sumsy::SuMSy, income::Currency = CUR_0)
    c = 1 - sumsy.dem_tiers
    balances = []


end