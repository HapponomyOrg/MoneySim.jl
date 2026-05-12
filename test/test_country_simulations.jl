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
                    @test Currency(row[:paid_tax] / income) == Currency(MoneySim.calculate_flat_gdp_tax(BE))
                end
            end

            counter += 1
            deposit = row[:deposit]
            income = row[:income]
        end
    end

    model_data = data[2]
    row_counter = 0
    gdp = 0

    for row in eachrow(model_data)
        if row_counter > 0
            # @test Currency(row[:collected_tax]) / Currency(row[:gdp]) == MoneySim.calculate_flat_gdp_tax(BE)
            println("GDP: ",
                    Currency(row[:gdp]),
                    " - Collected tax: ",
                    Currency(row[:collected_tax]),
                    " - Ratio: ",
                    Currency(row[:gdp]) > 0 ? Currency(row[:collected_tax]) / Currency(row[:gdp]) : "NA")
        end

        row_counter += 1
    end
end