module MoneySim

include("Simulation.jl")
export Mode, growth_mode, loan_ratio_mode
export SimData, FuncData, RealFunc, IntFunc
export simulate_banks, plot_data, simulations
export simulate_fixed_g, simulate_random_g, simulate_fixed_LR, simulate_random_LR
export curent_available, current_saved, current_money_stock, money_stock, debt_ratio, growth_ratio, profit_ratio, equity_ratio, loan_ratio, delta_growth_profitexport, print_last_ratio
export plot_multi_series, plot_maturity, plot_loan_ratio, plot_debt_ratio, plot_growth_ratio, plot_profit_ratio, plot_equity_ratio, plot_delta_growth_profit, plot_money_stock, plot_D_over_L
export random_float, random_int

include("SuMSySimulation.jl")
export BASIC_SUMSY, DEM_FREE_SUMSY, TIERED_SUMSY, DEM_FREE_TIERED_SUMSY, NO_DEM_SUMSY, NO_SUMSY, NO_GI_SUMSY
export run_sumsy_simulation
export yard_sale!, taxed_yard_sale!
export analyse_money_stock, plot_money_stock, plot_comparative_money_stock
export one_time_money_injection!, constant_money_injection!, one_time_money_destruction!, constant_money_destruction!, equal_money_distribution!
export plot_net_incomes

include("InequalitySimulation.jl")
export run_standard_yard_sale_simulation, run_transaction_based_sumsy_simulation
export analyse_wealth, plot_wealth, plot_outlier_wealth

end
