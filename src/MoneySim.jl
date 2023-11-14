module MoneySim

include("keynes_sim.jl")
export Mode, growth_mode, loan_ratio_mode
export SimData, FuncData, RealFunc, IntFunc
export simulate_banks, plot_data, simulations
export simulate_fixed_g, simulate_random_g, simulate_fixed_LR, simulate_random_LR
export curent_available, current_saved, current_money_stock, money_stock, debt_ratio, growth_ratio, profit_ratio, equity_ratio, loan_ratio, delta_growth_profitexport, print_last_ratio
export plot_multi_series, plot_maturity, plot_loan_ratio, plot_debt_ratio, plot_growth_ratio, plot_profit_ratio, plot_equity_ratio, plot_delta_growth_profit, plot_money_stock, plot_D_over_L
export random_float, random_int

include("transaction_models.jl")
export TransactionParams
export YardSaleParams, StandardYardSaleParams, TaxedYardSaleParams
export ConsumerSupplyParams, FixedConsumerSupplyParams, VariableConsumerSupplyParams

include("model_adaptations.jl")
export one_time_money_injection!, constant_money_injection!, one_time_money_destruction!, constant_money_destruction!, equal_money_distribution!

include("behaviors.jl")
export borrow_income, borrow_when_poor, borrow_when_rich, ubi_borrow_when_poor, ubi_borrow_when_poor_rich

include("transaction_sim.jl")
export SimParams, ModelMoneyModelParams, FixedWealthParams, SuMSyParams, DebtBasedParams
export run_fixed_wealth_simulation
export equal_wealth_distribution!, concentrated_wealth_distribution!
export percentage_gi_actors!, mixed_actors!, typed_gi_actors!
export run_sumsy_simulation
export run_debt_based_simulation

include("data_analysis.jl")
export analyse_money_stock, analyse_wealth, analyse_type_wealth

include("plotting.jl")
export plot_money_stock, plot_comparative_money_stock
export plot_net_incomes
export plot_wealth, plot_outlier_wealth, plot_type_wealth

include("sumsy_simulation.jl")
export run_sumsy_simulation, run_consumer_supplier_simulation

end
