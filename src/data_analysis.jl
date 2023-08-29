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
        total_wealth = sum(group[!, :wealth_data])
        money_stock = sum(group[!, :deposit_data])
        rows = eachrow(sort(group, :equity_data))
        wealth_values = zeros(Fixed(4), 1, 8)
        wealth_percentages = zeros(Fixed(4), 1, 8)

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