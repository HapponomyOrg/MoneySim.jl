using EconoSim
using Plots
using StatsPlots
using Random
using Agents
using DataFrames

NUM_ACTORS = 1000

SIM_LENGTH = 1000
NUM_TRANSACTIONS = 200

BASIC_SUMSY = SuMSy(2000, 0, 0.01, 30)
DEM_FREE_SUMSY = SuMSy(2000, 25000, 0.01, 30)
TIERED_SUMSY = SuMSy(2000, 0, [(0, 0.01), (50000, 0.02), (500000, 0.05), (1000000, 0.1), (10000000, 0.5), (50000000, 0.95)], 30)
TIERED_DEM_FREE_SUMSY = SuMSy(2000, 25000, [(0, 0.01), (50000, 0.02), (500000, 0.05), (1000000, 0.1), (10000000, 0.5), (50000000, 0.95)], 30)
NO_DEM_SUMSY = SuMSy(2000, 0, 0, 30)
NO_SUMSY = SuMSy(0, 0, 0, 30)
NO_GI_SUMSY = SuMSy(0, 0, 0.01, 30)

C_0_2 = Currency(0.2)
C_0 = Currency(0)
C_20 = Currency(20)

function set_random_seed()
    Random.seed!(35416816)
end

### Behaviors

function yard_sale_transfer!(target1, target2, model)
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

function yard_sale!(model)
    for i in 1:model.num_transactions
        target1 = random_agent(model)
        target2 = random_agent(model)
        yard_sale_transfer!(target1, target2, model)
    end
end

function taxed_yard_sale!(model)
    tax = 0.01

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
        book_asset!(destination, SUMSY_DEP, -transfer * tax)
    end
end

function equity_data(actor)
    return asset_value(actor.balance, SUMSY_DEP)
end

function deposit_data(actor)
    return asset_value(actor.balance, SUMSY_DEP)
end

function create_actors!(model,
                        num_actors::Integer,
                        start_balance::Real,
                        entry::BalanceEntry;
                        non_gi::Bool = false,
                        non_gi_override = nothing,
                        activate_sumsy = true)
    for i in 1:num_actors
        actor = activate_sumsy ? sumsy_actor() : Actor()
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
                        concentrated::Bool = false,
                        activate_sumsy = true)
    concentrated_balance = num_actors * start_balance
    actor_balance = concentrated ? 0 : start_balance
    actor_balance = add_non_gi ? actor_balance * num_actors / (num_actors + 0.25 * num_actors) : actor_balance

    num_gi_mod = 0
    num_non_gi_mod = 0

    if concentrated
        if add_non_gi
            create_actors!(model, 1, concentrated_balance, entry,
                            non_gi = true,
                            non_gi_override = non_gi_override,
                            activate_sumsy = activate_sumsy)
            num_non_gi_mod = -1
        else
            create_actors!(model, 1, Currency(concentrated_balance), entry,
            activate_sumsy = activate_sumsy)
            num_gi_mod = -1
        end
    end

    create_actors!(model, num_actors + num_gi_mod, actor_balance, entry,
                    activate_sumsy = activate_sumsy)

    if add_non_gi
        create_actors!(model, Integer(num_actors / 4) + num_non_gi_mod,
                        actor_balance, entry,
                        non_gi = true,
                        non_gi_override = non_gi_override,
                        activate_sumsy = activate_sumsy)
    end
end

function process_transaction_sumsy!(balance::Balance, model, step::Int; booking_function = book_net_result!)
    if is_sumsy_active(balance, sumsy) && process_ready(sumsy, step)
         seed = step == 0 ? get_seed(balance, sumsy) : CUR_0
         income = get_guaranteed_income(balance, sumsy)
         demurrage = calculate_demurrage(balance, sumsy, step)
         booking_function(balance, sumsy, seed, income, demurrage, step)
 
         return seed, income, demurrage
    else
         return CUR_0, CUR_0, CUR_0
    end
 end

function run_sumsy_simulation(sumsy::SuMSy = BASIC_SUMSY;
                                num_actors::Integer = NUM_ACTORS,
                                num_transactions::Integer = NUM_TRANSACTIONS,
                                sim_length::Integer = SIM_LENGTH,
                                add_non_gi::Bool = false,
                                concentrated::Bool = false,
                                transaction_model = yard_sale!,
                                model_adaptation::Union{Function, Nothing} = nothing)
    set_random_seed()
    start_balance = telo(sumsy) == CUR_MAX ? telo(BASIC_SUMSY) : telo(sumsy)
    model = create_sumsy_model(sumsy)
    model.properties[:num_transactions] = num_transactions
    model.properties[:last_transaction] = model.step

    if model_adaptation !== nothing
        add_model_behavior!(model, model_adaptation)
    end

    non_gi_override = add_non_gi ? sumsy_overrides(sumsy, guaranteed_income = 0) : nothing
    add_actors!(model, num_actors, start_balance, SUMSY_DEP, add_non_gi = add_non_gi, non_gi_override = non_gi_override, concentrated = concentrated)
    add_model_behavior!(model, transaction_model)

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

function plot_comparative_money_stock(dataframe,
                                        title::String = "";
                                        original_min = nothing,
                                        original_max = nothing,
                                        new_min = nothing,
                                        new_max = nothing)
    @df dataframe plot(:money_stock, title = "Money stock\n" * title, label = "new money stock", color = "blue")

    if original_min !== nothing
        plot!(fill(original_min, size(dataframe[!, :money_stock])[1]), label = "original min", color = "orange")
    end

    if original_max !== nothing
        plot!(fill(original_max, size(dataframe[!, :money_stock])[1]), label = "original max", color = "red")
    end

    if new_min !== nothing
        plot!(fill(new_min, size(dataframe[!, :money_stock])[1]), label = "new min", color = "green")
    end

    if new_max !== nothing
        plot!(fill(new_max, size(dataframe[!, :money_stock])[1]), label = "new max", color = "purple")
    end
end

function plot_money_stock_per_person(dataframe, num_actors = NUM_ACTORS, title::String = "")
    plot(./(dataframe[!, :money_stock], num_actors), title = "Money stock\n" * title, label = "Money stock")
end

function plot_net_incomes(sumsy::SuMSy)
    b = Balance()
    incomes = Vector{Currency}()

    for i in 0:10:telo(sumsy)
        append!(incomes,
                sumsy.guaranteed_income
                - calculate_demurrage(i, sumsy))
    end

    plot(incomes, label = "net income", xlabel="Acount balance", xticks = 10)
end

run_sumsy_simulation(sim_length = 10)