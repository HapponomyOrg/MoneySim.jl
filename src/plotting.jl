function plot_money_stock(dataframes::Union{DataFrame,Vector{DataFrame}},
    title::String="";
    money_stock_labels::Union{Vector{String},String}="money stock",
    theoretical_min=nothing,
    theoretical_max=nothing)
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

        min_money_stock = minimum(dataframes[i].money_stock)
        max_money_stock = maximum(dataframes[i].money_stock)

        if max_money_stock - min_money_stock < 1
            if isnothing(theoretical_min) && isnothing(theoretical_max)
                min_y = round(min_money_stock) - 0.5
                max_y = round(max_money_stock) + 0.5
            elseif isnothing(theoretical_min)
                min_y = theoretical_max - 0.5
                max_y = theoretical_max + 0.5
            elseif isnothing(theoretical_max)
                min_y = theoretical_min - 0.5
                max_y = theoretical_min + 0.5
            else
                min_y = theoretical_min - 0.5
                max_y = theoretical_max + 0.5
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
            p = @df dataframes[i] plot(:money_stock, title=title, label=label, yrange=(min_y, max_y), xlabel="Periods", ylabel="Money stock")
        else
            p = @df dataframes[i] plot!(:money_stock, label=label, yrange=(min_y, max_y), xlabel="Periods", ylabel="Money stock")
        end
    end

    if theoretical_min !== nothing
        p = plot!(fill(theoretical_min, data_size), label="min")
    end

    if theoretical_max !== nothing
        p = plot!(fill(theoretical_max, data_size), label="max")
    end

    return p
end

function plot_comparative_money_stock(dataframe,
    title::String="";
    original_min=nothing,
    original_max=nothing,
    new_min=nothing,
    new_max=nothing)
    @df dataframe plot(:money_stock, title=title, label="money stock", color="blue", xlabel="Periods", ylabel="Money stock")

    if original_min !== nothing
        plot!(fill(original_min, size(dataframe[!, :money_stock])[1]), label="original min", color="orange")
    end

    if original_max !== nothing
        plot!(fill(original_max, size(dataframe[!, :money_stock])[1]), label="original max", color="red")
    end

    if new_min !== nothing
        plot!(fill(new_min, size(dataframe[!, :money_stock])[1]), label="new min", color="green")
    end

    if new_max !== nothing
        plot!(fill(new_max, size(dataframe[!, :money_stock])[1]), label="new max", color="purple")
    end
end

function plot_money_stock_per_person(dataframe, num_actors=NUM_ACTORS, title::String="")
    plot(./(dataframe[!, :money_stock], num_actors), title=title, label="Money stock", xlabel="Periods", ylabel="Money stock")
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

function plot_wealth(dataframe, title::String="")
    @df dataframe plot([:bottom_10, :bottom_50, :middle_40, :top_10, :top_1, :top_0_1],
        title="Wealth distribution\n" * title,
        label=["Bottom 10" "Bottom 50" "Middle 40" "Top 10" "Top 1" "Top 0.1"],
        xlabel="Time",
        ylabel="Wealth %",
        legend=:legend)
end

function plot_outlier_wealth(dataframe, title::String)
    # for i in 1:250
    #     deleteat!(dataframe, 1)
    # end

    @df dataframe plot([:bottom_0_1, :bottom_1, :bottom_10, :top_10, :top_1, :top_0_1],
        title="Outlier wealth distribution\n" * title,
        label=["Bottom 0.1" "Bottom 1" "Bottom 10" "Top 10" "Top 1" "Top 0.1"],
        xlabel="Time",
        ylabel="Wealth %",
        ylims=[0, 100])
end