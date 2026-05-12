using DataFrames

@enum WealthType PERCENTAGE AVERAGE NOMINAL SCALED WEALTH_GINI INCOME_GINI

"""
    analyse_money_stock(dataframe,
                        data::Vector{Symbol} = [:deposit],
                        output_stocks::Vector{Symbol} = [:money_stock])

    * dataframe: a data frame returned by `run_simulation`.
    * data: a vector of symbols indicating the data to be analysed.
    * output_stocks: a vector of symbols indicating the stocks to be returned.
"""
function analyse_money_stock(dataframe::DataFrame,
                            data::Vector{Symbol} = [:deposit],
                            output_stocks::Vector{Symbol} = [:money_stock])
    groups = groupby(dataframe, :time)

    # Create data frame
    counter = 0
    analysis = DataFrame(cycle = Int64[])

    for stock in output_stocks
        analysis[!, stock] = Currency[]
    end

    for group in groups
        rows = eachrow(group)
        stock = Array{Currency}(undef, 1, length(data))

        for index in 1:length(data)
            stock[1, index] = sum(group[!, data[index]])
        end

        push!(analysis, [[rows[1][:time]] stock])

        counter += 1
    end

    return analysis
end

function calculate_gini(total::Real, rows, target::Symbol = :equity)
    num_actors = size(rows)[1]
    accumulated = 0
    area = 0

    for index in 1:num_actors
        area += 0.5 * (2 * accumulated + rows[index][target])
        accumulated += rows[index][target]
    end

    return round(1 - 2 * area / (num_actors * total), digits = 4)
end

"""
    analyse_wealth(data)

    * data: a data frame vector returned by `run_simulation`, containing two elements:
        1. data frame with actor wealth data
        2. data frame with population data

    * returns: a data frame tuple consisting of:
        1. data frame with aggregated wealth data
        2. data frame with nominal wealth data per percentile
        3. data frame with wealth distribution where the wealth of the top 0.1% has been scaled to 100.
           The wealth of the other percentiles have been scaled relatively.
           It indicates how much wealth a member of a percentile has for everey 100 a member of the top percentile has.
        4. data frame with the Gini coeficcient.
"""
function analyse_wealth(data)    
    wealth_groups = groupby(data[1], :time)

    # Create data frames
    aggregate = DataFrame(cycle = Int64[],
                        money_stock = Currency[],
                        total_wealth = Currency[])

    w_analysis = DataFrame(cycle = Int64[])
    a_analysis = DataFrame(cycle = Int64[])
    p_analysis = DataFrame(cycle = Int64[])
    gw_analysis = DataFrame(cycle = Int64[])
    gi_analysis = DataFrame(cycle = Int64[])
    scaled_analysis = DataFrame(cycle = Int64[])

    for percentile in instances(Percentiles)
        w_analysis[!, Symbol(percentile)] = Currency[]
        a_analysis[!, Symbol(percentile)] = Currency[]
        p_analysis[!, Symbol(percentile)] = Currency[]
        scaled_analysis[!, Symbol(percentile)] = Currency[]
    end

    gw_analysis[!, :wealth_gini] = Float64[]
    gi_analysis[!, :income_gini] = Float64[]

    counter = 1

    for group in wealth_groups
        percentile_ranges = calculate_percentile_ranges(length(eachrow(group)))
        total_wealth = sum(group[!, :equity])
        total_income = sum(group[!, :income])
        money_stock = sum(group[!, :deposit])
        rows = eachrow(sort(group, :equity))
        wealth_values = zeros(Currency, 1, 9)
        average_values = zeros(Currency, 1, 9)
        wealth_percentages = zeros(Currency, 1, 9)
        scaled_values = zeros(Currency, 1, 9)

        for index in length(percentile_ranges):-1:1
            for i in percentile_ranges[index]
                wealth_values[index] += rows[i][:equity]
            end

            wealth_percentages[index] = total_wealth != 0 ? 100 * wealth_values[index] / total_wealth : 0
            average_values[index] = wealth_values[index] / length(percentile_ranges[index])
            scaled_values[index] = 100 * wealth_values[index] / wealth_values[9]
        end

        push!(aggregate, [[rows[1][:time]] [money_stock] [total_wealth]])
        push!(w_analysis, [[rows[1][:time]] wealth_values])
        push!(a_analysis, [[rows[1][:time]] average_values])
        push!(p_analysis, [[rows[1][:time]] wealth_percentages])
        push!(gw_analysis, [[rows[1][:time]] calculate_gini(total_wealth, rows, :equity)])
        push!(gi_analysis, [[rows[1][:time]] calculate_gini(total_income, rows, :income)])
        push!(scaled_analysis, [[rows[1][:time]] scaled_values])
        counter += 1
    end

    wealth_dict = Dict{WealthType, DataFrame}([NOMINAL => w_analysis,
                                                PERCENTAGE => p_analysis,
                                                AVERAGE => a_analysis,
                                                SCALED => scaled_analysis,
                                                WEALTH_GINI => gw_analysis,
                                                INCOME_GINI => gi_analysis])

    return wealth_dict, aggregate
end

function analyse_wealth_per_type(data)
    type_groups = groupby(data, :types)

end

"""
    analyse_wealth_per_type(data, wealth_processing)

    * data: a data frame vector returned by `run_simulation`.
    * wealth_processing: a function that takes in a vector of wealth data and returns a single number.
                        The result of this function will be used in the analysis per type.

Returns a data frame with the wealth distribution per type
"""
function analyse_type_wealth(data, wealth_processing::Function = median)
    type_sets = unique(data[!, :types])
    types = []
    type_wealth = Dict{Symbol, Vector{Currency}}()

    for type_set in type_sets
        for type in type_set
            push!(types, type)
        end
    end

    unique!(types)

    groups = groupby(data, :time)
    analysis = DataFrame(cycle = Int64[])
    
    for type in types
        analysis[!, type] = Currency[]
        type_wealth[type] = Vector{Currency}()
    end

    for group in groups
        rows = eachrow(group)

        for row in rows
            for type in row.types
                push!(type_wealth[type], row.equity)
            end
        end

        type_wealth_vector = Vector{Any}(types)

        for type in types
            type_wealth_vector[findfirst(x -> x == type, type_wealth_vector)] = wealth_processing(type_wealth[type])
        end

        push!(analysis, [[rows[1][:time]] transpose(type_wealth_vector)])
    end

    return analysis
end

function analyse_income(data)
end