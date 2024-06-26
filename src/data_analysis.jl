using DataFrames

"""
    analyse_money_stock(data)

    * data: a data frame vector returned by `run_simulation`.
"""
function analyse_money_stock(data)
    groups = groupby(data, :time)

    # Create data frame
    counter = 0
    analysis = DataFrame(cycle = Int64[],
                        money_stock = Currency[],
                        total_wealth = Currency[])

    for group in groups
        rows = eachrow(group)
        total_wealth = sum(group[!, :equity_data])
        money_stock = sum(group[!, :deposit_data])

        push!(analysis, [[rows[1][:time]] [money_stock] [total_wealth]])

        counter += 1
    end

    return analysis
end

function calculate_percentile_numbers(num_actors::Int)
    BOTTOM_0_1 = 1:Int64(round(num_actors / 1000))
    BOTTOM_1 = 1:Int64(round(num_actors / 100))
    BOTTOM_10 = 1:Int64(round(num_actors / 10))
    BOTTOM_50 = 1:Int64(round(num_actors / 2))
    LOW_MIDDLE_40 = Int64(round(num_actors / 10 + 1)):Int64(round(num_actors / 2))
    HIGH_MIDDLE_40 = Int64(round(num_actors / 2 + 1)):Int64(round(num_actors - num_actors / 10))
    TOP_10 = Int64(round(num_actors - num_actors / 10 + 1)):num_actors
    TOP_1 = Int64(round(num_actors - num_actors / 100 + 1)):num_actors
    TOP_0_1 = Int64(round(num_actors + 1 - num_actors / 1000)):num_actors
    return [BOTTOM_0_1, BOTTOM_1, BOTTOM_10, BOTTOM_50, LOW_MIDDLE_40, HIGH_MIDDLE_40, TOP_10, TOP_1, TOP_0_1]
end

function analyse_wealth(data)    
    wealth_groups = groupby(data[1], :time)
    population_groups = groupby(data[2], :time)

    # Create data frame
    analysis = DataFrame(cycle = Int64[],
                        money_stock = Currency[],
                        total_wealth = Currency[],
                        p_bottom_0_1 = Currency[],
                        p_bottom_1 = Currency[],
                        p_bottom_10 = Currency[],
                        p_bottom_50 = Currency[],
                        p_low_middle_40 = Currency[],
                        p_high_middle_40 = Currency[],
                        p_top_10 = Currency[],
                        p_top_1 = Currency[],
                        p_top_0_1 = Currency[],
                        bottom_0_1 = Currency[],
                        bottom_1 = Currency[],
                        bottom_10 = Currency[],
                        bottom_50 = Currency[],
                        low_middle_40 = Currency[],
                        high_middle_40 = Currency[],
                        top_10 = Currency[],
                        top_1 = Currency[],
                        top_0_1 = Currency[])

    counter = 1

    for group in wealth_groups
        PERCENTILES = calculate_percentile_numbers(population_groups[counter][!, :num_actors][1])
        total_wealth = sum(group[!, :wealth_data])
        money_stock = sum(group[!, :deposit_data])
        rows = eachrow(sort(group, :equity_data))
        wealth_values = zeros(Currency, 1, 9)
        wealth_percentages = zeros(Currency, 1, 9)

        for index in 1:length(PERCENTILES)
            for i in PERCENTILES[index]
                wealth_values[index] += rows[i][:equity_data]
            end

            wealth_values[index] /= length(PERCENTILES[index])
            wealth_percentages[index] = total_wealth != 0 ? 100 * wealth_values[index] / total_wealth : 0
        end

        push!(analysis, [[rows[1][:time]] [money_stock] [total_wealth] wealth_percentages wealth_values])
        counter += 1
    end

    return analysis
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
                push!(type_wealth[type], row.wealth_data)
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