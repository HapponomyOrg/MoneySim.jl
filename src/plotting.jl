using DataFrames
using Plots

function plot_data(dataframe::DataFrame,
                    data_symbols::Vector{Symbol},
                    data_labels::Vector{String},
                    reference_symbols::Vector{Symbol} = Vector{Symbol}(),
                    reference_values::Vector{<:Real} = Vector{Real}(),
                    reference_labels::Vector{String} = Vector{String}(),
                    xlabel::String = "Years",
                    ylabel::String = "")
    data_size = size(dataframe)[1]
    the_plot = plot(dataframe[!, data_symbols[1]], label=data_labels[1], xlabel=xlabel, ylabel=ylabel)

    for i in 2:length(data_symbols)
        plot!(dataframe[!, data_symbols[i]], label=data_labels[i])
    end

    for i in 1:length(reference_symbols)
        plot!(fill(reference_values[i], data_size), label = reference_labels[i])
    end

    return the_plot
end

function plot_stocks(dataframes::Union{DataFrame,Vector{DataFrame}},
                    title::String="";
                    stock_symbol = :money_stock,
                    stock_label = "Money Stock",
                    time_label::String = "Periods",
                    money_stock_labels::Union{Vector{String},String, Nothing} = nothing,
                    min_label::String = "min",
                    max_label::String = "max",
                    theoretical_min=nothing,
                    theoretical_max=nothing)
    data_size = 0
    
    if typeof(dataframes) == DataFrame
        data_size = size(dataframes[!, stock_symbol])[1]
        dataframes = [dataframes]
    else
        data_size = size(dataframes[1][!, stock_symbol])[1]
    end

    if typeof(money_stock_labels) == String
        money_stock_labels = [money_stock_labels]
    end

    min_y = typemax(Currency)
    max_y = typemin(Currency)

    for i in eachindex(dataframes)
        min_stock = isnothing(theoretical_min) ? minimum(dataframes[i][!, stock_symbol]) : min(theoretical_min, minimum(dataframes[i][!, stock_symbol]))
        max_stock = isnothing(theoretical_max) ? maximum(dataframes[i][!, stock_symbol]) : max(theoretical_max, maximum(dataframes[i][!, stock_symbol]))

        if max_stock - min_stock < 1
            if isnothing(theoretical_min) && isnothing(theoretical_max)
                min_y = round(min_stock) - 0.5
                max_y = round(max_stock) + 0.5
            elseif isnothing(theoretical_min)
                min_y = min(min_stock, theoretical_max - 0.5)
                max_y = max(max_stock, theoretical_max + 0.5)
            elseif isnothing(theoretical_max)
                min_y = min(min_stock, theoretical_min - 0.5)
                max_y = max(max_stock, theoretical_min + 0.5)
            else
                min_y = min(min_stock, theoretical_min - 0.5)
                max_y = max(max_stock, theoretical_max + 0.5)
            end
        else
            if isnothing(theoretical_min) && isnothing(theoretical_max)
                min_y = min_stock - (max_stock - min_stock) / 10
                max_y = max_stock + (max_stock - min_stock) / 10
            elseif isnothing(theoretical_min)
                min_y = min_stock - (max(theoretical_max, max_stock) - min_stock) / 10
                max_y = max(theoretical_max, max_stock) + (max(theoretical_max, max_stock) - min_stock) / 10
            elseif isnothing(theoretical_max)
                min_y = min(theoretical_min, min_stock) - (max_stock - min(theoretical_min, min_stock)) / 10
                max_y = max_stock + (max_stock - min(theoretical_min, min_stock)) / 10
            else
                min_y = min(theoretical_min, min_stock) - (max(theoretical_max, max_stock) - min(theoretical_min, min_stock)) / 10
                max_y = max(theoretical_max, max_stock) + (max(theoretical_max, max_stock) - min(theoretical_min, min_stock)) / 10
            end
        end
    end

    for i in eachindex(dataframes)
        if !isnothing(money_stock_labels)
            label = money_stock_labels[i]
        else
            label = nothing
        end

        if i == 1
            p = plot(dataframes[i][!, stock_symbol], title=title, label=label, yrange=(min_y, max_y), xlabel=time_label, ylabel=stock_label)
        else
            p = plot(dataframes[i][!, stock_symbol], label=label, yrange=(min_y, max_y), xlabel=time_label, ylabel=stock_label)
        end
    end

    if theoretical_min !== nothing
        p = plot!(fill(theoretical_min, data_size), label = min_label)
    end

    if theoretical_max !== nothing
        p = plot!(fill(theoretical_max, data_size), label = max_label)
    end

    return p
end

function plot_comparative_stocks(dataframe,
                                title::String="";
                                stock_symbol = :money_stock,
                                stock_label = "Money Stock",
                                original_min=nothing,
                                original_max=nothing,
                                new_min=nothing,
                                new_max=nothing)
    p = plot(dataframe[!, stock_symbol], title=title, label=stock_label, color="blue", xlabel="Periods", ylabel=stock_label)

    if original_min !== nothing
        plot!(fill(original_min, size(dataframe[!, stock_symbol])[1]), label="original min", color="orange")
    end

    if original_max !== nothing
        plot!(fill(original_max, size(dataframe[!, stock_symbol])[1]), label="original max", color="red")
    end

    if new_min !== nothing
        plot!(fill(new_min, size(dataframe[!, stock_symbol])[1]), label="new min", color="green")
    end

    if new_max !== nothing
        plot!(fill(new_max, size(dataframe[!, stock_symbol])[1]), label="new max", color="purple")
    end
end

function plot_stocks_per_person(dataframe,
                                num_actors=NUM_ACTORS,
                                title::String="";
                                stock_symbol = :money_stock,
                                stock_label = "Money Stock")
    plot(./(dataframe[!, stock_symbol], num_actors), title=title, label=stock_label, xlabel="Periods", ylabel=stock_label)
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

function plot_gini_coefficients(data_dict::Dict{SimDataType, DataFrame};
                                gini_symbols::Vector{Symbol} = [:wealth_gini, :income_gini],
                                title::String = "Gini Coefficients",
                                xlabel::String = "Time",
                                ylabel::String = "Gini Coefficient",
                                labels::Vector{String} = ["Wealth Gini", "Income Gini"])    
    wealth_data = data_dict[WEALTH_GINI][!, gini_symbols[1]]
    wealth_data = [wealth_data[i] for i in findall(x -> x !== NaN, wealth_data)]

    income_data = data_dict[INCOME_GINI][!, gini_symbols[2]]
    income_data = [income_data[i] for i in findall(x -> x !== NaN, income_data)]

    the_plot = plot(wealth_data,
                    label = labels[1],
                    title = title,
                    xlabel = xlabel,
                    ylabel = ylabel,
                    yrange = (0, max(maximum(wealth_data),
                                    maximum(income_data),
                                    1.1)),
                    legend = :inside)

    plot!(income_data, label = labels[2])

    return the_plot
end

function plot_gini_rate(data_dict::Dict{SimDataType, DataFrame};
                        gini_symbols::Vector{Symbol} = [:wealth_gini, :income_gini],
                        title::String = "Gini Rate - Wealth / Income",
                        xlabel::String = "Time",
                        ylabel::String = "Gini Rate",
                        label::Union{String, Nothing} = nothing)
    wealth_data = data_dict[WEALTH_GINI]
    income_data = data_dict[INCOME_GINI]

    gini_rates = Vector{Currency}()
    wealth_rows = eachrow(wealth_data)
    income_rows = eachrow(income_data)

    for i in 1:length(wealth_rows)
        try
            append!(gini_rates, Currency(wealth_rows[i][gini_symbols[1]]
                                        / income_rows[i][gini_symbols[2]]))
        catch
        end
    end

    return plot(gini_rates,
                label = label,
                title = title,
                xlabel = xlabel,
                ylabel = ylabel,
                yrange = (0, maximum(gini_rates) + 0.1),
                legend = :inside)
end

function plot_data(data::Dict{SimDataType, DataFrame},
                    percentiles::Vector{Percentiles} = collect(instances(Percentiles));
                    title::String="",
                    xlabel::String = "Time",
                    labels = nothing,
                    type::SimDataType = W_PERCENTAGE)
    dataframe = deleteat!(copy(data[type]), 1)
    labels = isnothing(labels) ? percentiles_to_labels(percentiles) : labels
    ylabel = ""

    if type == W_PERCENTAGE
        ylabel *= "% Wealth"
    elseif type == W_AVERAGE
        ylabel = "Average Wealth"
    elseif type == W_NOMINAL
        ylabel *= "Wealth"
    elseif type == W_SCALED
        ylabel *= "Scaled Wealth"
    elseif type == I_PERCENTAGE
        ylabel *= "% Income"
    elseif type == W_AVERAGE
        ylabel = "Average Income"
    elseif type == W_NOMINAL
        ylabel *= "Income"
    elseif type == W_SCALED
        ylabel *= "Scaled Income"
    end

    the_plot = plot(
		dataframe[!, Symbol(percentiles[1])],
		label = labels[1],
		title = title,
		xlabel = xlabel,
		ylabel = ylabel,
        legend = :inside
	)

    for i in 2:length(percentiles)
        plot!(dataframe[!, Symbol(percentiles[i])], label=labels[i])
    end

    return the_plot
end

function plot_type_wealth(dataframes::Vector{DataFrame}, types::Vector{Symbol}, title = "", labels = nothing)
    types = unique(types)
    the_plot = plot_type_wealth(dataframes[1], types, title, isnothing(labels) ? nothing! : labels[1])

    for i in 2:length(dataframes)
        plot!([dataframes[i][!, type] for type in types],
            label=isnothing(labels) ? percentiles_to_labels(types) : labels[i])
    end

    return the_plot
end

function plot_type_wealth(dataframe::DataFrame, types::Vector{Symbol}, title = "", label = nothing)
    types = unique(types)

	plot(
		[dataframe[!, type] for type in types],
		label = isnothing(label) ? percentiles_to_labels(types) : label,
		title = title,
		xlabel ="Time",
		ylabel ="Median wealth"
	)
end

function percentile_to_label(p::Percentiles)
    label = string(p)
    label = replace(label, "0_1" => "0.1")
    label = replace(label, "_" => " ")
    label *= "%"
    label = uppercase(label[1]) * label[2:end]

    return label
end

function percentiles_to_labels(percentiles::Vector{Percentiles})
    labels = Vector{String}()

    for percentile in percentiles
        push!(labels, percentile_to_label(percentile))
    end

    return reshape([label for label in labels], 1, length(labels))
end

function plot_gdp(dataframe, title::String="GDP")
    df = copy(dataframe)
    deleteat!(df, 1)
    plot(df[!, :gdp], title=title, label="GDP", xlabel="Time", ylabel="GDP")
end

function plot_min_max_transactions(dataframe, title::String="Min/Max Transactions")
    df = copy(dataframe)
    deleteat!(df, 1)

    the_plot = plot(df[!, :min_transaction], title=title, label="Min transaction", xlabel="Time", ylabel="Transaction size")
    plot!(df[!, :max_transaction], label="Max transaction")

    return the_plot
end

function plot_transactions(dataframe, title::String="")
    df = copy(dataframe)
    deleteat!(df, 1)

    plot(df[!, :transactions], title=title, label="Transactions", xlabel="Time", ylabel="Transactions")
end

function plot_non_broke_actors(dataframe::DataFrame, title::String="")
    plot(dataframe[!, :non_broke_actors], title=title, label="Non broke actors", xlabel="Time", ylabel="Non broke actors")
end

function plot_collected_tax(full_tax_target::Real,
                            net_tax_target::Real,
                            real_income::Real,
                            dataframe::Union{DataFrame, Vector{DataFrame}},
                            labels::Union{String, Vector{String}},
                            title::String="Collected taxes")
    if typeof(dataframe) == DataFrame
        dataframes = [copy(dataframe)]
    else
        dataframes = Vector{DataFrame}()

        for i in 1:length(dataframe)
            push!(dataframes, copy(dataframe[i]))
        end
    end

    for i in 1:length(dataframes)
        deleteat!(dataframes[i], 1)
    end

    if typeof(labels) == String
        labels = [labels]
    end

    the_plot = plot(fill(full_tax_target, size(dataframes[1][!, :collected_tax])[1]),
                    label="Full Tax Target",
                    color="red",
                    title=title,
                    xlabel = "Years",
                    ylabel = "Tax",
                    legend = :inside)
    plot!(fill(net_tax_target, size(dataframes[1][!, :collected_tax])[1]), label="Net Tax Target", color="blue")
    plot!(fill(real_income, size(dataframes[1][!, :collected_tax])[1]), label="Real income", color="green")

    for i in 1:length(dataframe)
        plot!(dataframes[i][!, :collected_tax], label=labels[i])
    end

    for i in 1:length(dataframe)
        plot!(dataframes[i][!, :collected_tax] + dataframes[i][!, :collected_vat], label=labels[i] * " + VAT")
    end

    return the_plot
end

function plot_expenses(data, title::String = "Expenses vs Revenue")
    data = copy(data)
    deleteat!(data, 1)

    total_revenue = Vector{Currency}()

    for row in eachrow(data)
        append!(total_revenue, row[:collected_tax] + row[:collected_vat])
    end

    the_plot = plot(total_revenue, title=title, label="Total Revenue", xlabel="Time", ylabel="Amount")  
    plot!(data[!, :projected_expenses], label="Target expenses") 
    
    return the_plot
end

function plot_tax_brackets(data, title::String = "Tax Brackets")
    labels = names(data)
    the_plot = plot(data[!, labels[1]], title=title, label=labels[1], xlabel="Time", ylabel="Percentage", legend=:inside)

    for i in 2:length(labels)
        plot!(data[!, labels[i]], label=labels[i])
    end

    return the_plot
end