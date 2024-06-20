using EconoSim
using MoneySim
using Agents
using Statistics
using Plots
using CSV

# GI = 2000
# d = 0.01
# tu = 30

# N_GI = 1000
# Y = 200
# L = 10

# basic_sumsy = SuMSy(GI, 0, d, tu, transactional = false)

# tiers = [(0, 0.01), (50000, 0.02), (500000, 0.05), (1000000, 0.1), (10000000, 0.5), (50000000, 0.95)]
# tiered_sumsy = SuMSy(GI, 0, tiers, tu)

set_currency_precision!(4)

# function MoneySim.run_sumsy_simulation(sumsy::SuMSy;
#                                         economic_strength::UnitRange{Int} = 200:200,
#                                         model_adaptations::Vector{<: Function} = Vector{Function}(),
#                                         sim_length = L)
#     sim_length *= tu

#     sim_params = SimParams(sim_length, tu)

#     initial_wealth = telo(sumsy)

#     sumsy_params = SuMSyParams(initial_wealth, 0)
                                
#     transaction_params = StandardYardSaleParams(N_GI, economic_strength,0.2:0.2:0.2, 0)

#     data = run_sumsy_simulation(sim_params,
#                                 sumsy_params,
#                                 transaction_params,
#                                 model_adaptations)

#     return analyse_wealth(data, N_GI)
# end

# function run_standard_simulation(economic_strength::UnitRange{Int} = 200:200,
#                                     model_adaptations::Vector{<: Function} = Vector{Function}();
#                                     sim_length = L)
#     sim_length *= tu
#     sim_params = SimParams(sim_length, tu)
#     fixed_wealth_params = FixedWealthParams(200000, true)
#     yard_sale_params = StandardYardSaleParams(N_GI, economic_strength,0.2:0.2:0.2, 0)

#     data = run_fixed_wealth_simulation(sim_params,
#                                         yard_sale_params,
#                                         fixed_wealth_params,
#                                         model_adaptations)

#     return analyse_wealth(data, N_GI)
# end

# function run_debt_based_simulation(economic_strength::UnitRange{Int} = 200:200,
#                                     model_adaptations::Vector{<: Function} = Vector{Function}())
# end

# function fund_large_project(model)
#     sumsy = model.sumsy
#     step = model.step
#     amount = 1000

#     if step < sumsy.interval * 15 * 12 && process_ready(sumsy, step)
#         for actor in allagents(model)
#             book_asset!(get_balance(actor), SUMSY_DEP, amount)
#         end
#     end
# end

# function constant_injection(model)
#     sumsy = model.sumsy
#     step = model.step
#     amount = 1000

#     if process_ready(sumsy, step)
#         for actor in allagents(model)
#             book_asset!(get_balance(actor), SUMSY_DEP, amount)
#         end
#     end
# end

# plot(m_data.money_stock)

# plot_money_stock(analyse_money_stock(data))

# run_standard_simulation()

# plt = plot([0,0.1], Any[rand(2),sin])
# for x in 0.2:0.1:π
#     push!(plt, 1, x, rand())
#     push!(plt, 2, x, sin(x))
#     gui(); sleep(0.5)
# end

# a_data, m_data = run_fixed_wealth_gdp_simulation(population = 1000,
#                                     m2 = 620000000000 / 11590,
#                                     gdp = 550000000000 / 11590,
#                                     years = 50)

# for i in [0.01, 0.03, 0.05]
#     sumsy = SuMSy(2000, 0, i, 30)
#     df = run_sumsy_simulation(sumsy,
#                             eligible_actors = 1000,
#                             num_transactions = 200,
#                             sim_length = 500)[1]
#     dfa = analyse_wealth(df, 1000)
#     CSV.write("Raw data - Demurrage = $(i*100)%.csv", df)
#     CSV.write("Wealth analysis - Demurrage = $(i*100)%.csv", dfa)
# end

# GI = 2000
# d = 0.01
# tu = 30

# N_GI = 100
# Y = 200
# L = 500

# basic_sumsy = SuMSy(GI, 0, d, tu)

# function wealth_distribution(sumsy::SuMSy, title::String)
#     println(title)
#     println("Telo: " * string(telo(sumsy)))
#     df = run_sumsy_simulation(sumsy, eligible_actors = 1000, num_transactions = 200, sim_length = 500)
#     dfa = analyse_wealth(df[1], 1000)
#     println("Top 1%: " * string(mean(dfa[!, :top_1])) * "%")
#     println("Top 10%: " * string(mean(dfa[!, :top_10])) * "%")
#     println("Middle 40%: " * string(mean(dfa[!, :middle_40])) * "%")
#     println("Bottom 50%: " * string(mean(dfa[!, :bottom_50])) * "%")
# end

# wealth_distribution(SuMSy(2000, 0, 0.01, 30), "Basic SuMSy (1%)")
# wealth_distribution(SuMSy(2000, 0, 0.05, 30), "Basic SuMSy (5%)")
# wealth_distribution(SuMSy(2000, 0, [(0, 0.05), (50000, 0.1), (500000, 0.25), (500000, 0.5), (1000000, 0.75), (5000000, 0.95)], 30), "Tiered SuMSy")
# wealth_distribution(SuMSy(2000, 0, [(0, 0.05), (50000, 0.1), (100000, 0.25), (500000, 0.5), (1000000, 0.75), (5000000, 0.95), (10000000, 1)], 30), "Limitarism SuMSy 10 mil")
# wealth_distribution(SuMSy(2000, 0, [(0, 0.05), (50000, 0.1), (100000, 0.25), (500000, 0.5), (1000000, 0.75), (5000000, 1)], 30), "Limitarism SuMSy 5 mil")

# plot_money_stock(
#     analyse_money_stock(
#         run_sumsy_simulation(basic_sumsy,
#                             eligible_actors = N_GI,
#                             num_transactions = Y,
#                             sim_length = L,
#                             distributed = true,
#                             model_adaptation = one_time_money_injection!)[1]),
#     "One-off Money Injection Event",
#     theoretical_max = telo(basic_sumsy) * N_GI)

# GI = 2000
# d = 0.01
# tu = 30

# N_GI = 100
# Y = 200
# L = 150

# basic_sumsy = SuMSy(GI, 0, d, tu)

# plot_money_stock(
#     analyse_money_stock(
#         run_sumsy_simulation(basic_sumsy,
#                             eligible_actors = N_GI,
#                             num_transactions = Y,
#                             sim_length = L,
#                             distributed = true)[1]), # distribute money
#     "Money Stock - Equal Initial Distribution",
#     theoretical_max = telo(GI, d) * N_GI)

