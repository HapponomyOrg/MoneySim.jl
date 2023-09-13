function analyse_money_stock(data)
    groups = groupby(data, :step)

    # Create data frame
    counter = 0
    analysis = DataFrame(cycle = Int64[],
                        money_stock = Currency[],
                        total_wealth = Currency[])

    for group in groups
        rows = eachrow(group)
        total_wealth = sum(group[!, :equity_data])
        money_stock = sum(group[!, :deposit_data])

        push!(analysis, [[rows[1][:step]] [money_stock] [total_wealth]])

        counter += 1
    end

    return analysis
end

function analyse_wealth(data, num_actors::Int)
    BOTTOM_0_1 = 1:Int64(round(num_actors / 1000))
    BOTTOM_1 = 1:Int64(num_actors / 100)
    BOTTOM_10 = 1:Int64(num_actors / 10)
    BOTTOM_50 = 1:Int64(num_actors / 2)
    MIDDLE_40 = Int64(num_actors / 2 + 1):Int64(num_actors - num_actors / 10)
    TOP_10 = Int64(num_actors - num_actors / 10 + 1):num_actors
    TOP_1 = Int64(num_actors - num_actors / 100 + 1):num_actors
    TOP_0_1 = Int64(round(num_actors + 1 - num_actors / 1000)):num_actors
    PERCENTILES = [BOTTOM_0_1, BOTTOM_1, BOTTOM_10, BOTTOM_50, MIDDLE_40, TOP_10, TOP_1, TOP_0_1]
    
    groups = groupby(data, :step)

    # Create data frame
    analysis = DataFrame(cycle = Int64[],
                        money_stock = Currency[],
                        total_wealth = Currency[],
                        bottom_0_1 = Currency[],
                        bottom_1 = Currency[],
                        bottom_10 = Currency[],
                        bottom_50 = Currency[],
                        middle_40 = Currency[],
                        top_10 = Currency[],
                        top_1 = Currency[],
                        top_0_1 = Currency[])

    for group in groups
        total_wealth = sum(group[!, :wealth_data])
        money_stock = sum(group[!, :deposit_data])
        rows = eachrow(sort(group, :equity_data))
        wealth_values = zeros(Currency, 1, 8)
        wealth_percentages = zeros(Currency, 1, 8)

        for index in 1:length(PERCENTILES)
            for i in PERCENTILES[index]
                wealth_values[index] += rows[i][:equity_data]
            end

            wealth_percentages[index] = total_wealth != 0 ? 100 * wealth_values[index] / total_wealth : 0
        end

        push!(analysis, [[rows[1][:step]] [money_stock] [total_wealth] wealth_percentages])
    end

    return analysis
end