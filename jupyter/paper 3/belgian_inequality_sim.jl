using EconoSim
using MoneySim
using CSV

const ZETA = 0.02 # 0.0037
const NUM_ACTORS = 10000

function c1_be_calibration()
    d_data = simulate_country(BE,
                                sim_length = 100 * YEAR,
                                data_collection_interval = YEAR,
                                lock_random_generator = false,
                                num_actors = NUM_ACTORS,
                                monetary_type = M_FIXED,
                                population_type = P_FIXED,
                                wealth_distribution = W_UNEQUAL,
                                wealth_transfer = 0.2,
                                wealth_accumulation_advantage = ZETA,
                                taxes = T_GDP_FLAT_TAX,
                                tax_interval = MONTH,
                                vat_active = false,
                                vat_interval = MONTH)

    d_dfa = analyse_wealth(d_data)

    CSV.write("data/c1_actor_data.csv", d_data[1], bufsize = 100000000)
    CSV.write("data/c1_model_data.csv", d_data[2], bufsize = 100000000)

    CSV.write("data/c1_money_stock.csv", d_dfa[2], bufsize = 100000000)

    CSV.write("data/c1_wealth_gini.csv", d_dfa[1][WEALTH_GINI])
    CSV.write("data/c1_income_gini.csv", d_dfa[1][INCOME_GINI])

    plot_wealth(d_dfa[1],
                [TOP_0_1, TOP_1, TOP_10, HIGH_MIDDLE_40, LOW_MIDDLE_40, BOTTOM_10, BOTTOM_1],
                title = "Yard Sale Model - GDP Belgium",
                xlabel = "Years",
                labels = ["Top 0.1%", "Top 1%", "Top 10%", "High Middle 40%", "Low Middle 40%", "Bottom 10%", "Bottom 1%"],
                type = PERCENTAGE)
end

function b1_baseline()
    d_data = MoneySim.simulate_fixed_belgium(sim_length = 500 * MoneySim.YEAR,
                                        num_actors = 10000,
                                        sumsy = false,
                                        inequality_data = MoneySim.INEQUALITY_DATA_BE,
                                        waa = ZETA,
                                        tax_type = nothing)

    d_dfa = analyse_wealth(d_data)

    CSV.write("data/average_wealth.csv", d_dfa[1][AVERAGE])
    CSV.write("data/percentage_wealth.csv", d_dfa[1][PERCENTAGE])

    plot_wealth(d_dfa[1],
                [TOP_0_1, TOP_1, TOP_10, HIGH_MIDDLE_40, LOW_MIDDLE_40, BOTTOM_10, BOTTOM_1],
                title = "Yard Sale Model - GDP Belgium",
                xlabel = "Years",
                labels = ["Top 0.1%", "Top 1%", "Top 10%", "High Middle 40%", "Low Middle 40%", "Bottom 10%", "Bottom 1%"],
                type = PERCENTAGE)
end