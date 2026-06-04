using DataFrames

@enum WealthType W_PERCENTAGE W_AVERAGE W_NOMINAL W_SCALED WEALTH_GINI I_PERCENTAGE I_AVERAGE I_NOMINAL I_SCALED INCOME_GINI

"""
    analyse_aggregate(dataframe,
                        data::Vector{Symbol} = [:deposit],
                        output_stocks::Vector{Symbol} = [:money_stock])

    * dataframe: a data frame returned by `run_simulation`.
    * data: a vector of symbols indicating the data to be analysed.
    * output_aggregates: a vector of symbols indicating the aggregates to be returned.
"""
function analyse_aggregate(dataframe::DataFrame,
                            data::Vector{Symbol} = [:deposit],
                            output_stocks::Vector{Symbol} = [:money_stock])
    groups = groupby(dataframe, :time)

    # Create data frame
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
    end

    return analysis
end

function calculate_gini(total::Real, rows, target::Symbol = :deposit)
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
    analyse_data(data)

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
function analyse_data(data, wealth::Symbol = :deposit, income::Symbol = :income)    
    wealth_groups = groupby(data[1], :time)

    # Create data frames
    wealth_analysis = DataFrame(cycle = Int64[])
    wealth_average_analysis = DataFrame(cycle = Int64[])
    wealth_percentage_analysis = DataFrame(cycle = Int64[])
    wealth_gini_analysis = DataFrame(cycle = Int64[])
    
    scaled_wealth_analysis = DataFrame(cycle = Int64[])

    income_analysis = DataFrame(cycle = Int64[])
    income_average_analysis = DataFrame(cycle = Int64[])
    income_percentage_analysis = DataFrame(cycle = Int64[])
    income_gini_analysis = DataFrame(cycle = Int64[])
    
    scaled_income_analysis = DataFrame(cycle = Int64[])

    for percentile in instances(Percentiles)
        wealth_analysis[!, Symbol(percentile)] = Currency[]
        wealth_average_analysis[!, Symbol(percentile)] = Currency[]
        wealth_percentage_analysis[!, Symbol(percentile)] = Currency[]
        
        scaled_wealth_analysis[!, Symbol(percentile)] = Currency[]

        income_analysis[!, Symbol(percentile)] = Currency[]
        income_average_analysis[!, Symbol(percentile)] = Currency[]
        income_percentage_analysis[!, Symbol(percentile)] = Currency[]
        
        scaled_income_analysis[!, Symbol(percentile)] = Currency[]
    end

    wealth_gini_analysis[!, :wealth_gini] = Float64[]
    income_gini_analysis[!, :income_gini] = Float64[]

    counter = 1

    for group in wealth_groups
        percentile_ranges = calculate_percentile_ranges(length(eachrow(group)))
        total_wealth = sum(group[!, wealth])
        total_income = sum(group[!, income])
        
        wealth_rows = eachrow(sort(group, wealth))
        income_rows = eachrow(sort(group, income))

        wealth_values = zeros(Currency, 1, 9)
        average_wealth_values = zeros(Currency, 1, 9)
        wealth_percentages = zeros(Currency, 1, 9)
        scaled_wealth_values = zeros(Currency, 1, 9)

        income_values = zeros(Currency, 1, 9)
        average_income_values = zeros(Currency, 1, 9)
        income_percentages  = zeros(Currency, 1, 9)
        scaled_income_values = zeros(Currency, 1, 9)

        for index in length(percentile_ranges):-1:1
            for i in percentile_ranges[index]
                wealth_values[index] += wealth_rows[i][wealth]
                income_values[index] += income_rows[i][income]
            end

            wealth_percentages[index] = total_wealth != 0 ? 100 * wealth_values[index] / total_wealth : 0
            average_wealth_values[index] = wealth_values[index] / length(percentile_ranges[index])
            scaled_wealth_values[index] = 100 * wealth_values[index] / wealth_values[9] # Scales to the wealth of the richest

            income_percentages[index] = total_income != 0 ? 100 * income_values[index] / total_income : 0
            average_income_values[index] = income_values[index] / length(percentile_ranges[index])
            scaled_income_values[index] = 100 * income_values[index] / income_values[9]
        end

        push!(wealth_analysis, [[wealth_rows[1][:time]] wealth_values])
        push!(wealth_average_analysis, [[wealth_rows[1][:time]] average_wealth_values])
        push!(wealth_percentage_analysis, [[wealth_rows[1][:time]] wealth_percentages])
        push!(wealth_gini_analysis, [[wealth_rows[1][:time]] calculate_gini(total_wealth, wealth_rows, wealth)])

        push!(scaled_wealth_analysis, [[wealth_rows[1][:time]] scaled_wealth_values])

        push!(income_analysis, [[income_rows[1][:time]] income_values])
        push!(income_average_analysis, [[income_rows[1][:time]] average_income_values])
        push!(income_percentage_analysis, [[income_rows[1][:time]] income_percentages])
        push!(income_gini_analysis, [[income_rows[1][:time]] calculate_gini(total_income, income_rows, income)])

        push!(scaled_income_analysis, [[income_rows[1][:time]] scaled_income_values])
        
        counter += 1
    end

    wealth_dict = Dict{WealthType, DataFrame}([W_NOMINAL => wealth_analysis,
                                                W_PERCENTAGE => wealth_percentage_analysis,
                                                W_AVERAGE => wealth_average_analysis,
                                                W_SCALED => scaled_wealth_analysis,
                                                WEALTH_GINI => wealth_gini_analysis,
                                                I_NOMINAL => income_analysis,
                                                I_PERCENTAGE => income_percentage_analysis,
                                                I_AVERAGE => income_average_analysis,
                                                I_SCALED => scaled_income_analysis,
                                                INCOME_GINI => income_gini_analysis])

    return wealth_dict
end

"""
    analyse_type_data(data, data_processing)

    * data: a data frame vector returned by `run_simulation`.
    * data_processing: a function that takes in a vector of wealth data and returns a single number.
                        The result of this function will be used in the analysis per type.

Returns a data frame with the wealth distribution per type
"""
function analyse_type_data(data, data_processing::Function = median)
    type_sets = unique(data[!, :types])
    types = []
    type_data = Dict{Symbol, Vector{Currency}}()

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
        type_data[type] = Vector{Currency}()
    end

    for group in groups
        rows = eachrow(group)

        for row in rows
            for type in row.types
                push!(type_data[type], row.equity)
            end
        end

        type_data_vector = Vector{Any}(types)

        for type in types
            type_data_vector[findfirst(x -> x == type, type_data_vector)] = data_processing(type_data[type])
        end

        push!(analysis, [[rows[1][:time]] transpose(type_data_vector)])
    end

    return analysis
end

function analyse_income(data)
end