using EconoSim
using Plots
using StatsPlots
using Random
using Agents
using DataFrames

NUM_ACTORS = 100

SIM_LENGTH = 100
NUM_TRANSACTIONS = 200

BASIC_SUMSY = SuMSy(2000, 0, 0.01, 30)
TRANSACTIONAL_SUMSY = SuMSy(2000, 0, 0.01, 30, transactional = true)
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
    Random.seed!(3564651616568)
end

### Behaviors

function randomize_direction(target1::AbstractActor,
                            av1::Currency,
                            target2::AbstractActor,
                            av2::Currency)
    transfer = max(C_0,
            Currency(min(av1, av2) * C_0_2))

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

function yard_sale_transfer!(target1::AbstractActor,
                                target2::AbstractActor,
                                model::ABM)
    av1 = max(CUR_0, sumsy_assets(target1, model.step))
    av2 = max(CUR_0, sumsy_assets(target2, model.step))

    source, destination, transfer = randomize_direction(target1,
                                                        av1,
                                                        target2,
                                                        av2)
    
    transfer_sumsy!(source, destination, transfer)
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

        source, destination, transfer = randomize_direction(target1,
                                                            av1,
                                                            target2,
                                                            av2)    
        
        transfer_asset!(source, destination, SUMSY_DEP, transfer)
        book_asset!(destination, SUMSY_DEP, -transfer * tax)
    end
end

function equity_data(actor)
    return asset_value(get_balance(actor), SUMSY_DEP)
end

function deposit_data(actor)
    return sumsy_assets(actor, actor.model.step)
end

function create_actors!(model::ABM,
                        num_actors::Integer,
                        start_balance::Real,;
                        non_gi::Bool = false,
                        activate_sumsy = true)
    for i in 1:num_actors
        if activate_sumsy
            actor = add_single_sumsy_actor!(model, gi_eligible = !non_gi, initialize = false)
        else
            actor = add_actor!(model, MonetaryActor())
        end

        actor.model = model
        book_asset!(get_balance(actor), SUMSY_DEP, start_balance)
    end
end

function add_actors!(model::ABM,
                        num_actors::Integer,
                        start_balance::Real;
                        add_non_gi::Bool = false,
                        concentrated::Bool = false,
                        activate_sumsy = true)
    concentrated_balance = num_actors * start_balance
    actor_balance = concentrated ? 0 : start_balance
    actor_balance = add_non_gi ? actor_balance * num_actors / (num_actors + 0.25 * num_actors) : actor_balance

    num_gi_mod = 0
    num_non_gi_mod = 0

    if concentrated
        if add_non_gi
            create_actors!(model, 1, Currency(concentrated_balance),
                            non_gi = true,
                            activate_sumsy = activate_sumsy)
            num_non_gi_mod = -1
        else
            create_actors!(model, 1, Currency(concentrated_balance),
                            activate_sumsy = activate_sumsy)
            num_gi_mod = -1
        end
    end

    create_actors!(model, num_actors + num_gi_mod, actor_balance,
                                activate_sumsy = activate_sumsy)

    if add_non_gi
        create_actors!(model, Integer(round(num_actors / 4)) + num_non_gi_mod,
                        actor_balance,
                        non_gi = true,
                        activate_sumsy = activate_sumsy)
    end
end

function collect_data(model::ABM, step::Int)
    return mod(step, model.sumsy.interval) == 0
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

    if sumsy.transactional
        model = create_unremovable_single_sumsy_model(sumsy)
    else
        model = create_unremovable_single_sumsy_model(sumsy, model_behaviors = process_model_sumsy!)
    end
    
    model.properties[:num_transactions] = num_transactions
    model.properties[:last_transaction] = model.step

    if model_adaptation !== nothing
        add_model_behavior!(model, model_adaptation)
    end

    add_actors!(model, num_actors, start_balance, add_non_gi = add_non_gi, concentrated = concentrated)
    add_model_behavior!(model, transaction_model)

    data, _ = run_econo_model!(model, sim_length * sumsy.interval , adata = [deposit_data, equity_data], when = collect_data)

    return data
end

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

function analyse_money_stock(data)
    groups = groupby(data, :step)

    # Create data frame
    counter = 0
    analysis = DataFrame(cycle = Int64[],
                        money_stock = Fixed(4)[],
                        total_wealth = Fixed(4)[])

    for group in groups
        rows = eachrow(group)
        total_wealth = sum(group[!, :equity_data])
        money_stock = sum(group[!, :deposit_data])

        push!(analysis, [[rows[1][:step]] [money_stock] [total_wealth]])

        counter += 1
    end

    return analysis
end

function plot_money_stock(dataframes::Union{DataFrame, Vector{DataFrame}},
                            title::String = "";
                            money_stock_labels::Union{Vector{String}, String} = "money stock",
                            theoretical_min = nothing,
                            theoretical_max = nothing)
    data_size = 0

    if typeof(dataframes) == DataFrame
        data_size = size(dataframes[!, :money_stock])[1]
        dataframes = [dataframes]
    else
        data_size = size(dataframes[1][!, :money_stock])[1]
    end

    if typeof(money_stock_labels) == String
        money_stock_labels = [money_stock_labels]
    end

    for i in 1:length(dataframes)
        label = money_stock_labels[i]

        min_money_stock = typemax(Currency) 
        max_money_stock = typemin(Currency)

        for j in 1:data_size
            min_money_stock = min(min_money_stock, Currency(dataframes[i][j, :money_stock]))
            max_money_stock = max(max_money_stock, Currency(dataframes[i][j, :money_stock]))
        end

        if max_money_stock - min_money_stock < 4
            if isnothing(theoretical_min) && isnothing(theoretical_max)
                min_y = round(max_money_stock - 5)
                max_y = round(max_money_stock + 1)
            elseif isnothing(theoretical_min)
                min_y = theoretical_max - 2
                max_y = theoretical_max + 2
            elseif isnothing(theoretical_max)
                min_y = theoretical_min - 2
                max_y = theoretical_min + 2
            else
                min_y = theoretical_min - 2
                max_y = theoretical_max + 2
            end
        else
            if isnothing(theoretical_min) && isnothing(theoretical_max)
                min_y = min_money_stock - (max_money_stock - min_money_stock) / 10
                max_y = max_money_stock + (max_money_stock - min_money_stock) / 10
            elseif isnothing(theoretical_min)
                min_y = min_money_stock - (max(theoretical_max, max_money_stock) - min_money_stock) / 10
                max_y = max(theoretical_max, max_money_stock) + (max(theoretical_max, max_money_stock) - min_money_stock) / 10
            elseif isnothing(theoretical_max)
                min_y = min(theoretical_min, min_money_stock) - (max_money_stock - min(theoretical_min, min_money_stock)) / 10
                max_y = max_money_stock + (max_money_stock - min(theoretical_min, min_money_stock)) / 10
            else
                min_y = min(theoretical_min, min_money_stock) - (max(theoretical_max, max_money_stock) - min(theoretical_min, min_money_stock)) / 10
                max_y = max(theoretical_max, max_money_stock) + (max(theoretical_max, max_money_stock) - min(theoretical_min, min_money_stock)) / 10
            end
        end

        if i == 1
            @df dataframes[i] plot(:money_stock, title = title, label = label, yrange = (min_y, max_y), xlabel = "Periods", ylabel = "Money stock")
        else
            @df dataframes[i] plot!(:money_stock, label = label, yrange = (min_y, max_y), xlabel = "Periods", ylabel = "Money stock")
        end
    end

    if theoretical_min !== nothing
        plot!(fill(theoretical_min, data_size), label = "min")
    end

    if theoretical_max !== nothing
        plot!(fill(theoretical_max, data_size), label = "max")
    end
end

function plot_comparative_money_stock(dataframe,
                                        title::String = "";
                                        original_min = nothing,
                                        original_max = nothing,
                                        new_min = nothing,
                                        new_max = nothing)
    @df dataframe plot(:money_stock, title = title, label = "money stock", color = "blue", xlabel = "Periods", ylabel = "Money stock")

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
    plot(./(dataframe[!, :money_stock], num_actors), title = title, label = "Money stock", xlabel = "Periods", ylabel = "Money stock")
end

function plot_net_incomes(sumsy::SuMSy)
    # balance = CUR_0
    # incomes = Vector{Currency}()

    # for i in 0:10:telo(sumsy)
    #     adjust
    #     append!(incomes, calculate_timerange_adjustments(balance::Real, sumsy::SuMSy, gi_eligible::Bool, timerange::Int))
    # end

    # plot(incomes, label = "net income", xlabel="Acount balance", xticks = 10)
end