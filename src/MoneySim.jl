module MoneySim

include("Simulation.jl")

export Mode, growth_mode, loan_ratio_mode
export SimData, RealFunc, IntFunc
export simulate_banks, plot_data, simulations
export plot_maturity, plot_loan_ratio, plot_debt_ratio, plot_growth_ratio, plot_profit_ratio, plot_delta_growth_profit, plot_money_stock, plot_D_over_L
export random_float, random_int

end
