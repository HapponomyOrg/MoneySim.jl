module MoneySim

include("Simulation.jl")

export Mode, growth_mode, loan_ratio_mode
export SimData, RealFunc, IntFunc
export simulate_banks, plot_data, simulations
export curent_available, current_saved, current_money_stock, money_stock, debt_ratio, growth_ratio, profit_ratio, delta_growth_profitexport, print_last_ratio
export plot_maturity, plot_loan_ratio, plot_debt_ratio, plot_growth_ratio, plot_profit_ratio, plot_delta_growth_profit, plot_money_stock, plot_D_over_L
export random_float, random_int

end
