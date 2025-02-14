using EconoSim
using MoneySim
using Test
using Agents

GI = 2000
d = 0.01
tu = 30

N_GI = 1000
Y = 200
L = 150

basic_sumsy = SuMSy(GI, 0, d, tu, transactional = false)
transactional_sumsy = SuMSy(GI, 0, d, tu, transactional = true)

raw_data = run_sumsy_simulation(basic_sumsy,
                            eligible_actors = N_GI,
                            num_transactions = Y,
                            sim_length = L,
                            distributed = true)

# raw_data = run_sumsy_simulation(transactional_sumsy,
#                                 eligible_actors = N_GI,
#                                 num_transactions = Y,
#                                 sim_length = L,
#                                 distributed = true)
data = analyse_money_stock(raw_data)
low = minimum(data.money_stock)
mid = telo(basic_sumsy) * N_GI
high = maximum(data.money_stock)

off_high = high / mid * 100 - 100
off_low = low / mid * 100 - 100

(off_high, off_low)

# plot_money_stock(data,
#                     "Transactional demurrage",
#                     theoretical_max = telo(basic_sumsy) * N_GI)