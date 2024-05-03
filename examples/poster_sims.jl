using EconoSim
using MoneySim
using Agents
using CSV

sim_params = SimParams(30 * 12 * 23, 30 * 12, lock_random_generator = true)

# Population history in Europe from 2001 to 2023 in millions of inhabitants.
# Data source population: https://www.statista.com/statistics/1106711/population-of-europe/
population = [727, 727, 727, 728, 729, 730, 731, 733, 735, 736, 738, 739, 740, 741, 742, 743, 744, 745, 746, 746, 745, 744, 742]

# A SuMSy model is created that results in an account balance of 20,000.
# This is the average amount of money per person in the EU in 2021.
# Data source M2: https://tradingeconomics.com/euro-area/money-supply-m2
m2 = 15300000 # million
money_supply_per_capita = m2 / population[end]
gi = 2000
d = gi / money_supply_per_capita
sumsy = SuMSy(gi, 0, d, 30)

# Every year the population is adjusted to be in line with the historical data
function adjust_population!(model::ABM)
     if model.step % (30 * 12) == 0 && nagents(model) != population[Int(round(model.step / (30 * 12)))]
        population_adjustment = population[Int(round(model.step / (30 * 12)))] - nagents(model)

        if population_adjustment > 0
            for _ in 1:population_adjustment
                agent = add_actor!(model, make_single_sumsy!(model, sumsy, MonetaryActor(model), initialize = false))
                set_last_adjustment!(agent.balance, model.step)
            end
        else
            for _ in 1:abs(population_adjustment)
                dead_agent = random_agent(model)
                heir = random_agent(model)

                while dead_agent == heir
                    heir = random_agent(model)
                end

                transfer_sumsy!(model, dead_agent, heir, asset_value(get_balance(dead_agent), SUMSY_DEP))

                remove_agent!(dead_agent, model)
            end
        end

     end
end

model = create_single_sumsy_model(sumsy, model_behaviors = [adjust_population!, process_model_sumsy!])
transaction_params = NoTransactionParams(727)
sumsy_params = StandardSuMSyParams(telo(sumsy))

# Money stock simulation
data = run_simulation(model, sim_params, transaction_params, sumsy_params)
mdata = analyse_money_stock(data[1])

CSV.write("data/Poster - Money stock EU.csv", mdata)

# Inequality simulation
# Inequality data source: https://wid.world/world/

gdp_collector(actor) = actor.model.gdp
transactions_collector(actor) = actor.model.transactions
data_collectors = [equity_collector, wealth_collector, deposit_collector, :types, gdp_collector, transactions_collector]

# EU GDP 2021
# Data source population: https://www.statista.com/statistics/1106711/population-of-europe/
# GDP data source: https://www.statista.com/statistics/279447/gross-domestic-product-gdp-in-the-european-union-eu/#:~:text=In%202022%20the%20gross%20domestic,economic%20strength%20of%20a%20country.
# Data source M2: https://tradingeconomics.com/euro-area/money-supply-m2
M2 = 13800000 # million
population = 745 # million
money_supply_per_capita = M2 / population
gdp = 14640036 # million
d = gi / money_supply_per_capita
sumsy = SuMSy(gi, 0, d, 30)
inequality_data = InequalityData(nothing,   # Top 0.1% - not applicable
                                1566407,    # Top 1%
                                381336,     # Top 10%
                                23422,      # High middle 40%
                                7177,       # Low middle 40%
                                -2236,      # Bottom 10%
                                -45198,     # Bottom 1%
                                nothing)    # Bottom 0.1% - not applicable
sumsy_params = InequalitySuMSyParams(inequality_data)
gdp_yard_sale_params = GDPYardSaleParams(1000, gdp / population * 1000, 360, 0.2:0.2, 0.0, gdp_yard_sale!)

eu_data = run_sumsy_simulation(sumsy,
                                sim_params,
                                gdp_yard_sale_params,
                                sumsy_params,
                                actor_data_collectors = data_collectors)
eu_wdata = analyse_wealth(eu_data[1], 1000)

CSV.write("data/Poster - Inequality EU.csv", eu_wdata)

# Belgium GDP 2021
# Data source population: https://www.statista.com/statistics/516667/total-population-of-belgium/
# GDP data source: https://www.statista.com/statistics/524844/gross-domestic-product-gdp-in-belgium/
# Data source M2: https://tradingeconomics.com/belgium/money-supply-m2
M2 = 610000 # million
population = 11.55 # million
money_supply_per_capita = M2 / population
gdp = 502311 # million
d = gi / money_supply_per_capita
sumsy = SuMSy(gi, 0, d, 30)
gdp_yard_sale_params = GDPYardSaleParams(1000, gdp / population * 1000, 360, 0.2:0.2, 0.0, gdp_yard_sale!)
inequality_data = InequalityData(nothing,   # Top 0.1% - not applicable
                                3821141,    # Top 1%
                                1329362,    # Top 10%
                                102098,     # High middle 40%
                                48944,      # Low middle 40%
                                -754,       # Bottom 10%
                                -42272,     # Bottom 1%
                                nothing)    # Bottom 0.1% - not applicable
sumsy_params = InequalitySuMSyParams(inequality_data)

be_data = run_sumsy_simulation(sumsy,
                                sim_params,
                                gdp_yard_sale_params,
                                sumsy_params,
                                actor_data_collectors = data_collectors)
be_wdata = analyse_wealth(be_data[1], 1000)

CSV.write("data/Poster - Inequality Belgium.csv", be_wdata)

# Netherlands GDP 2021
# Data source population: https://www.statista.com/statistics/519720/total-population-of-the-netherlands/
# GDP data source: https://www.statista.com/statistics/529063/the-netherlands-gdp/
# Data source M2: https://tradingeconomics.com/netherlands/money-supply-m2
# M2 = 937000 M euro
M2 = 937000 # million
population = 17.48 # million
money_supply_per_capita = M2 / population
gdp = 856360 # million
d = gi / money_supply_per_capita
sumsy = SuMSy(gi, 0, d, 30)
inequality_data = InequalityData(nothing,   # Top 0.1% - not applicable
                                4345950,    # Top 1%
                                1483226,    # Top 10%
                                148748,     # High middle 40%
                                76646,      # Low middle 40%
                                2141,       # Bottom 10%
                                7241,       # Bottom 1%
                                nothing)    # Bottom 0.1% - not applicable                                					
sumsy_params = InequalitySuMSyParams(inequality_data)
gdp_yard_sale_params = GDPYardSaleParams(1000, gdp / population * 1000, 360, 0.2:0.2, 0.0, gdp_yard_sale!)

nl_data = run_sumsy_simulation(sumsy,
                                sim_params,
                                gdp_yard_sale_params,
                                sumsy_params,
                                actor_data_collectors = data_collectors)
                                nl_wdata = analyse_wealth(nl_data[1], 1000)

CSV.write("data/Poster - Inequality Netherlands.csv", nl_wdata)