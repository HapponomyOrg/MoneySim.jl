using Test
using EconoSim
using MoneySim
using Agents
using FixedPointDecimals
using DataFrames

@testset "Country Simulation - barebones" begin  
    data = simulate_country(BE,
                            sim_length = 13 * MONTH,
                            data_collection_interval = MONTH,
                            num_actors = 2,
                            monetary_type = M_FIXED,
                            population_type = P_FIXED,
                            wealth_distribution = W_EQUAL,
                            wealth_accumulation_advantage = 0,
                            taxes = T_GDP_FLAT_TAX,
                            vat_active = false)
    
    actor_data = data[1]
    actor_groups = groupby(actor_data, :id)

    for actor_group in actor_groups
        counter = 0
        deposit = 0
        income = 0

        for row in eachrow(actor_group)
            if counter > 0
                # @test row[:deposit] - row[:income] + row[:expenses] + row[:paid_tax] + row[:tax_share] == deposit

                if income != 0
                    # The income of one month is taxed in the next. calculate_flat_gdp_tax was renamed to
                    # calculate_flat_gdp_income_tax; the rate does not depend on the period.
                    @test isapprox(row[:paid_tax] / income,
                                    MoneySim.calculate_flat_gdp_income_tax(BE, period = MONTH),
                                    atol = 1e-4)
                end
            end

            counter += 1
            deposit = row[:deposit]
            income = row[:income]
        end
    end

    # The government collects exactly what the actors pay.
    model_data = data[2]

    for (row, group) in zip(eachrow(model_data), groupby(actor_data, :time))
        @test row[:collected_tax] == sum(group[!, :paid_tax])
    end

    @test nrow(model_data) == 14
end
