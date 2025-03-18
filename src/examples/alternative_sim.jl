# This file contains all the code to generate the graphs in the paper:
# "An Alternative General-Purpose Money Supply Model for a Future-Proof Sustainable Economy"
using EconoSim
using MoneySim

function simulation_a1()
    GI = 2000
    d = 0.01
    tu = 30

    N_GI = 100
    Y = 200
    L = 150

    basic_sumsy = SuMSy(GI, 0, d)

    plot_money_stock(
        analyse_money_stock(
            run_sumsy_simulation(basic_sumsy,
                                sumsy_interval = tu,
                                eligible_actors = N_GI,
                                num_transactions = Y,
                                sim_length = L,
                                distributed = true)[1]), # distribute money
        "Money Stock - Equal Initial Distribution",
        theoretical_max = telo(GI, d) * N_GI)
end

function simulation_a2()GI = 2000
    d = 0.01
    tu = 30
    
    N_GI = 100
    Y = 200
    L = 150

    basic_sumsy = SuMSy(GI, 0, d)
    
    plot_money_stock(
        analyse_money_stock(
            run_sumsy_simulation(basic_sumsy,
                                sumsy_interval = tu,
                                eligible_actors = N_GI,
                                num_transactions = Y,
                                sim_length = L,
                                distributed = false)[1]), # concentrate money
        "Money Stock - Initially Concentrated",
        theoretical_max = telo(GI, d) * N_GI)
end

function simulation_b1()GI = 2000
    d = 0.01
    tu = 30
    
    N_GI = 100
    Y = 200
    L = 150

    basic_sumsy = SuMSy(GI, 0, d)
    
    plot_money_stock(
        analyse_money_stock(
            run_sumsy_simulation(basic_sumsy,
                                sumsy_interval = tu,
                                eligible_actors = N_GI,
                                non_eligible_actors = 25,
                                num_transactions = Y,
                                sim_length = L,
                                distributed = true)[1]), # distribute money
        "Money Stock - Equal Initial Distribution",
        theoretical_max = telo(GI, d) * N_GI)
end

function simulation_b2()GI = 2000
    d = 0.01
    tu = 30
    
    N_GI = 100
    Y = 200
    L = 150

    basic_sumsy = SuMSy(GI, 0, d)
    
    plot_money_stock(
        analyse_money_stock(
            run_sumsy_simulation(basic_sumsy,
                                sumsy_interval = tu,
                                eligible_actors = N_GI,
                                non_eligible_actors = 25,
                                num_transactions = Y,
                                sim_length = L,
                                distributed = false)[1]), # concentrate money
        "Money Stock - Initially Concentrated",
        theoretical_max = telo(GI, d) * N_GI)
end

function simulation_s1()GI = 2000
    d = 0.01
    tu = 30
    
    N_GI = 100
    Y = 200
    L = 750

    basic_sumsy = SuMSy(GI, 0, d)
    
    plot_money_stock(
        analyse_money_stock(
            run_sumsy_simulation(basic_sumsy,
                                sumsy_interval = tu,
                                eligible_actors = N_GI,
                                num_transactions = Y,
                                sim_length = L,
                                distributed = true,
                                model_adaptation = one_time_money_injection!)[1]),
        "One-off Money Injection Event",
        theoretical_max = telo(GI, d) * N_GI)
end

function simulation_s2()
    GI = 2000
    d = 0.01
    tu = 30

    N_GI = 100
    Y = 200
    L = 750

    basic_sumsy = SuMSy(GI, 0, d)

    plot_comparative_money_stock(
        analyse_money_stock(
            run_sumsy_simulation(basic_sumsy,
                                sumsy_interval = tu,
                                eligible_actors = N_GI,
                                num_transactions = Y,
                                sim_length = L,
                                distributed = true,
                                model_adaptation = constant_money_injection!)[1]),
        "Continuous Money Injection",
        original_max = telo(basic_sumsy) * N_GI,
        new_max = telo(GI, d) * N_GI + N_GI * GI / 2 / d)
end

function simulation_s3()
    GI = 2000
    d = 0.01
    tu = 30

    N_GI = 100
    Y = 200
    L = 750

    basic_sumsy = SuMSy(GI, 0, d)

    plot_money_stock(
        analyse_money_stock(
            run_sumsy_simulation(basic_sumsy,
                                sumsy_interval = tu,
                                eligible_actors = N_GI,
                                num_transactions = Y,
                                sim_length = L,
                                distributed = true,
                                model_adaptation = one_time_money_destruction!)[1]),
            "One-off Money Destruction Event",
            theoretical_max = telo(GI, d) * N_GI)
end

function simulation_s4()
    GI = 2000
    d = 0.01
    tu = 30

    N_GI = 100
    Y = 200
    L = 750

    basic_sumsy = SuMSy(GI, 0, d)

    plot_comparative_money_stock(
        analyse_money_stock(
            run_sumsy_simulation(basic_sumsy,
                                sumsy_interval = tu,
                                eligible_actors = N_GI,
                                num_transactions = Y,
                                sim_length = L,
                                distributed = true,
                                model_adaptation = constant_money_destruction!)[1]),
        "Continuous Money Destruction",
        original_max = telo(GI, d) * N_GI,
        new_max = telo(GI, d) * N_GI - GI * N_GI / 2 / d)
end

function simulation_e1()
    GI = 2000
    d = 0.01
    tu = 30

    N_GI = 100
    Y = 200
    L = 750

    DF = 25000
    dem_free_sumsy = SuMSy(GI, DF, d)

    plot_money_stock(
        analyse_money_stock(
            run_sumsy_simulation(dem_free_sumsy,
                                sumsy_interval = tu,
                                eligible_actors = N_GI,
                                num_transactions = Y,
                                sim_length = L,
                                distributed = true)[1]),
            "Demurrage-free Buffers",
            theoretical_min = telo(GI, d) * N_GI + DF,
            theoretical_max = telo(GI, d, DF) * N_GI)
end

function simulation_e2()
    GI = 2000
    d = [(0, 0.01), (50000, 0.02), (500000, 0.05), (1000000, 0.1), (10000000, 0.5), (50000000, 0.95)]
    tu = 30

    N_GI = 100
    Y = 200
    L = 750

    tiered_sumsy = SuMSy(GI, 0, d)

    plot_money_stock(
        analyse_money_stock(
            run_sumsy_simulation(tiered_sumsy,
                                sumsy_interval = tu,
                                eligible_actors = N_GI,
                                num_transactions = Y,
                                sim_length = L,
                                distributed = true)[1]),
        "Tiered Demurrage",
        theoretical_min = telo(GI * N_GI, d),
        theoretical_max = telo(GI, d) * N_GI)
end

function simulation_e3()
    GI = 2000
    d = [(0, 0.01), (50000, 0.02), (500000, 0.05), (1000000, 0.1), (10000000, 0.5), (50000000, 0.95)]
    tu = 30

    N_GI = 100
    Y = 0
    L = 750

    tiered_sumsy = SuMSy(GI, 0, d)

    plot_money_stock(
        analyse_money_stock(
            run_sumsy_simulation(tiered_sumsy,
                                sumsy_interval = tu,
                                eligible_actors = N_GI,
                                non_eligible_actors = 25, # add 25 actors with non-eligible accounts
                                num_transactions = Y,
                                sim_length = L,
                                model_adaptation = equal_money_distribution!,
                                distributed = true)[1]),
        "Tiered Demurrage",
        theoretical_min = telo(GI * N_GI, d),
        theoretical_max = telo(GI, d) * N_GI)
end

function simulation_e4()
    GI = 2000
    d = [(0, 0.01), (50000, 0.02), (500000, 0.05), (1000000, 0.1), (10000000, 0.5), (50000000, 0.95)]
    tu = 30

    N_GI = 100
    Y = 0
    L = 750

    tiered_sumsy = SuMSy(GI, 0, d)

    GI_eq = GI * N_GI / (N_GI + 25)
    new_sumsy = SuMSy(GI_eq, 0, d)

    plot_money_stock(
        analyse_money_stock(
            run_sumsy_simulation(tiered_sumsy,
                                sumsy_interval = tu,
                                eligible_actors = N_GI,
                                non_eligible_actors = 25, # add 25% actors with non-eligible accounts
                                num_transactions = Y,
                                sim_length = L,
                                model_adaptation = equal_money_distribution!,
                                distributed = true)[1]),
        "Tiered Demurrage",
        theoretical_min = telo(GI * N_GI, d),
        theoretical_max = telo(GI_eq, d) * (N_GI + 25))
end

function simulation_e5()
    GI = 2000
    d = [(0, 0.01), (50000, 0.02), (500000, 0.05), (1000000, 0.1), (10000000, 0.5), (50000000, 0.95)]
    tu = 30

    N_GI = 100
    Y = 200
    L = 750

    tiered_sumsy = SuMSy(GI, 0, d)
    new_sumsy = SuMSy(GI * N_GI / (N_GI + 25), 0, d)

    GI_eq = GI * N_GI / (N_GI + 25)

    plot_money_stock(
        analyse_money_stock(
            run_sumsy_simulation(tiered_sumsy,
                                sumsy_interval = tu,
                                eligible_actors = N_GI,
                                non_eligible_actors = 25, # add 25 actors with non-eligible accounts
                                num_transactions = Y,
                                sim_length = L,
                                distributed = true)[1]),
        "Tiered Demurrage",
        theoretical_min = telo(GI * N_GI, d),
        theoretical_max = telo(GI_eq, d) * (N_GI + 25))
end

function simulation_r1()
    GI = 2000
    d = 0.01
    tu = 30

    basic_sumsy = SuMSy(GI, 0, d)

    L = 1500

    b_data_1 = analyse_type_wealth(
                    run_consumer_supplier_simulation(basic_sumsy,
                                                    sumsy_interval = tu,
                                                    sim_length = L,
                                                    num_suppliers = 1,
                                                    consumers_per_supplier = 50,
                                                    fulfilled_demand = 5,
                                                    net_profit = 1,
                                                    suppliers_gi_eligible = false)[1])
    b_data_2 = analyse_type_wealth(
                    run_consumer_supplier_simulation(basic_sumsy,
                                                    sumsy_interval = tu,
                                                    sim_length = L,
                                                    num_suppliers = 1,
                                                    consumers_per_supplier = 100,
                                                    fulfilled_demand = 5,
                                                    net_profit = 1,
                                                    suppliers_gi_eligible = false)[1])
    b_data_3 = analyse_type_wealth(
                    run_consumer_supplier_simulation(basic_sumsy,
                                                    sumsy_interval = tu,
                                                    sim_length = L,
                                                    num_suppliers = 1,
                                                    consumers_per_supplier = 100,
                                                    fulfilled_demand = 3,
                                                    net_profit = 2,
                                                    suppliers_gi_eligible = false)[1])
    return b_data_1, b_data_2, b_data_3
end

function plot_fig_r1(b_data_1, b_data_2, b_data_3)
    plot_type_wealth([b_data_1, b_data_2, b_data_3],
                    [:supplier],
                    "Supplier Balances",
                    ["B1 - C = 50, RD = 5, FD = 5, NP = 1",
                    "B2 - C = 100, RD = 5, FD = 5, NP = 1",
                    "B3 - C = 100, RD = 5, FD = 3, NP = 2"])
end

function output_r1(b_data_1, b_data_2, b_data_3)
    b_balance_1 = b_data_1.supplier[end]
    b_balance_2 = b_data_2.supplier[end]
    b_balance_3 = b_data_3.supplier[end]

    println("C = 50, RD = 5, FD = 5, NP = 1, NI = 7,500 - Balance B1 = "
            * string(round(b_balance_1, digits = 2))
            * " = 100.0%")
    println("C = 100, RD = 5, FD = 5, NP = 1, NI = 15,000 - Balance B2 = "
            * string(round(b_balance_2, digits = 2))
            * " = "
            * string(round(b_balance_2
            * 100 / b_balance_1, digits = 2))
            * "% B1")
    println("C = 100, RD = 5, FD = 3, NP = 2, NI = 18,000 - Balance B3 = "
            * string(round(b_balance_3, digits = 2))
            * " = "
            * string(round(b_balance_3
            * 100 / b_balance_1, digits = 2))
            * "% B1")
end

function simulation_r2()
    GI = 2000
    d = [(0, 0.01), (50000, 0.02), (500000, 0.05), (1000000, 0.1), (10000000, 0.5), (50000000, 0.95)]
    tu = 30

    tiered_sumsy = SuMSy(GI, 0, d)

    L = 1500

    t_data_1 = analyse_type_wealth(
                    run_consumer_supplier_simulation(tiered_sumsy,
                                                    sumsy_interval = tu,
                                                    sim_length = L,
                                                    num_suppliers = 1,
                                                    consumers_per_supplier = 50,
                                                    fulfilled_demand = 5,
                                                    net_profit = 1,
                                                    suppliers_gi_eligible = false)[1])
    t_data_2 = analyse_type_wealth(
                    run_consumer_supplier_simulation(tiered_sumsy,
                                                    sumsy_interval = tu,
                                                    sim_length = L,
                                                    num_suppliers = 1,
                                                    consumers_per_supplier = 100,
                                                    fulfilled_demand = 5,
                                                    net_profit = 1,
                                                    suppliers_gi_eligible = false)[1])
    t_data_3 = analyse_type_wealth(
                    run_consumer_supplier_simulation(tiered_sumsy,
                                                    sumsy_interval = tu,
                                                    sim_length = L,
                                                    num_suppliers = 1,
                                                    consumers_per_supplier = 100,
                                                    fulfilled_demand = 3,
                                                    net_profit = 2,
                                                    suppliers_gi_eligible = false)[1])
    return t_data_1, t_data_2, t_data_3
end

function plot_fig_r2(t_data_1, t_data_2, t_data_3)
    plot_type_wealth([t_data_1, t_data_2, t_data_3],
                        [:supplier],
                        "Supplier Balances",
                        ["T1 - C = 50, RD = 5, FD = 5, NP = 1",
                        "T2 - C = 100, RD = 5, FD = 5, NP = 1",
                        "T3 - C = 100, RD = 5, FD = 3, NP = 2"])
end

function output_r2(t_data_1, t_data_2, t_data_3)
    t_balance_1 = t_data_1.supplier[end]
    t_balance_2 = t_data_2.supplier[end]
    t_balance_3 = t_data_3.supplier[end]

    println("C = 50, RD = 5, FD = 5, NP = 1, NI = 7.500 - Balance T1 = "
            * string(round(t_balance_1, digits = 2))
            * " = 100.0%")
    println("C = 100, RD = 5, FD = 5, NP = 1, NI = 15,000 - Balance T2 = "
            * string(round(t_balance_2, digits = 2))
            * " = "
            * string(round(t_balance_2
            * 100 / t_balance_1, digits = 2))
            * "% T1")
    println("C = 100, RD = 5, FD = 3, NP = 2, NI = 18,000 - Balance T3 = "
            * string(round(t_balance_3, digits = 2))
            * " = "
            * string(round(t_balance_3
            * 100 / t_balance_1, digits = 2))
            * "% T1")
end

function simulation_d1()
    GI = 2000
    d = 0.01
    tu = 30

    N_GI = 100
    Y = 200
    L = 150

    transactional_sumsy = SuMSy(GI, 0, d)

    plot_money_stock(
        analyse_money_stock(
            run_sumsy_simulation(transactional_sumsy,
                                sumsy_interval = tu,
                                sumsy_transactional = true,
                                eligible_actors = N_GI,
                                num_transactions = Y,
                                sim_length = L,
                                distributed = true)[1]),
            "Transactional Demurrage",
        money_stock_labels = "transactional",
        theoretical_max = telo(transactional_sumsy) * N_GI)
end