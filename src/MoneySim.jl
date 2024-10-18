module MoneySim

using EconoSim

include("utils.jl")
export BROKE_THRESHOLD
export is_broke, one_non_broke
export remove_index

include("population.jl")
export PopulationParams
export PopulationVectorParams, FixedPopulationParams, VaryingPopulationParams
export adjust_vector_population!
export create_sumsy_actor!
export kill_broke_actors!

include("keynes_sim.jl")
export Mode, growth_mode, loan_ratio_mode
export SimData, FuncData, RealFunc, IntFunc
export simulate_banks, plot_data, simulations
export simulate_fixed_g, simulate_random_g, simulate_fixed_LR, simulate_random_LR
export curent_available, current_saved, current_money_stock, money_stock, debt_ratio, growth_ratio, profit_ratio, equity_ratio, loan_ratio, delta_growth_profitexport, print_last_ratio
export plot_multi_series, plot_maturity, plot_loan_ratio, plot_debt_ratio, plot_growth_ratio, plot_profit_ratio, plot_equity_ratio, plot_delta_growth_profit, plot_money_stock, plot_D_over_L
export random_float, random_int

include("data_handler.jl")
export DataHandler, NoDataHandler, IntervalDataHandler
export initialize_data_handler!, post_process!

include("data_handler_utils.jl")
export equity_collector, wealth_collector, deposit_collector
export sumsy_equity_collector, sumsy_wealth_collector, sumsy_deposit_collector, sumsy_data_collector
export full_post_processing!, full_sumsy_post_processing!, money_stock_post_processing!, gdp_post_processing!
export NO_DATA_HANDLER
export full_data_handler, full_sumsy_data_handler, money_stock_data_handler, gdp_data_handler
export do_collect_data

include("transaction_models.jl")
export TransactionParams
export NoTransactionParams
export YardSaleParams, StandardYardSaleParams, TaxedYardSaleParams, GDPYardSaleParams
export ConsumerSupplyParams, FixedConsumerSupplyParams, VariableConsumerSupplyParams
export gdp_yard_sale!, gdp_baseline_yard_sale!

include("model_adaptations.jl")
export one_time_money_injection!, constant_money_injection!, one_time_money_destruction!, constant_money_destruction!, equal_money_distribution!

include("behaviors.jl")
export borrow_income, borrow_when_poor, borrow_when_rich, ubi_borrow_when_poor, ubi_borrow_when_poor_rich

include("money_models.jl")
export ModelMoneyModelParams, FixedWealthParams, StandardSuMSyParams, InequalitySuMSyParams, InequalityData, DebtBasedParams
export equal_wealth_distribution!, concentrated_wealth_distribution!, inequal_wealth_distribution!
export percentage_gi_actors!, mixed_actors!, typed_gi_actors!

include("data_analysis.jl")
export Percentiles, BOTTOM_0_1, BOTTOM_1, BOTTOM_10, BOTTOM_50, LOW_MIDDLE_40, MIDDLE_50, HIGH_MIDDLE_40, TOP_10, TOP_1, TOP_0_1
export WealthType, PERCENTAGE, NOMINAL, SCALED
export analyse_money_stock, analyse_wealth, analyse_type_wealth

include("termination_handler.jl")
export TerminationHandler, NoTerminationHandler, FlaggedTerminationHandler
export initialize_termination_handler!

include("termination_handler_utils.jl")
export NO_TERMINATION, TERMINATE_WHEN_ONE_NON_BROKE
export terminate_at_end_interval

include("plotting.jl")
export plot_data
export plot_money_stock, plot_comparative_money_stock
export plot_net_incomes
export plot_wealth, plot_outlier_wealth, plot_type_wealth
export plot_gdp, plot_transactions, plot_min_max_transactions
export plot_non_broke_actors

include("simulations.jl")
export SimParams
export run_simulation
export run_fixed_wealth_simulation, run_fixed_wealth_gdp_simulation
export run_sumsy_simulation, run_sumsy_gdp_simulation
export run_consumer_supplier_simulation
export run_debt_based_simulation

end
