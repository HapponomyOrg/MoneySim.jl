using EconoSim
using MoneySim
using CSV
using DataFrames
using Plots

const ZETA = 0.035
const NUM_ACTORS = 10000
const DIR = pwd()

struct YardSalePlots
    wealth
    income
    gini
    gini_rate
    money_stock
    debt_stock
    expenses
    tax_brackets
end

function write_data(data_dir::String,
                    data::Tuple{DataFrame, DataFrame},
                    dfa::Dict{SimDataType, DataFrame},
                    dm::DataFrame)
    mkpath(DIR * "/data/" * data_dir)
    cd(DIR * "/data/" * data_dir)

    CSV.write("actor_data.csv", data[1], bufsize = 100000000)
    CSV.write("model_data.csv", data[2], bufsize = 100000000)

    CSV.write("percentile_wealth_data.csv", dfa[W_PERCENTAGE])
    CSV.write("gini_wealth.csv", dfa[WEALTH_GINI])

    CSV.write("percentile_income_data.csv", dfa[I_PERCENTAGE])
    CSV.write("gini_income.csv", dfa[INCOME_GINI])

    CSV.write("money_stock.csv", dm)
    cd(DIR)
end

function read_data(data_dir::String)
    cd(DIR * "/data/" * data_dir)
    dfa = Dict{SimDataType, DataFrame}()

    actor_data = CSV.read("actor_data.csv", DataFrame)
    model_data = CSV.read("model_data.csv", DataFrame)

    dfa[W_PERCENTAGE] = CSV.read("percentile_wealth_data.csv", DataFrame)
    dfa[WEALTH_GINI] = CSV.read("gini_wealth.csv", DataFrame)

    dfa[I_PERCENTAGE] = CSV.read("percentile_income_data.csv", DataFrame)
    dfa[INCOME_GINI] = CSV.read("gini_income.csv", DataFrame)

    dm = CSV.read("money_stock.csv", DataFrame)

    cd(DIR)

    return actor_data, model_data, dfa, dm
end

function create_plots(actor_data::DataFrame,
                        model_data::DataFrame,
                        dfa::Dict{SimDataType, DataFrame},
                        dm::DataFrame;
                        money_debt::Bool = true,
                        taxes_expenses::Bool = true)    
    w_plot = plot_data(dfa,
                [TOP_0_1, TOP_1, TOP_10, HIGH_MIDDLE_40, LOW_MIDDLE_40, BOTTOM_10, BOTTOM_1],
                xlabel = "Years",
                labels = ["Top 0.1%", "Top 1%", "Top 10%", "High Middle 40%", "Low Middle 40%", "Bottom 10%", "Bottom 1%"],
                type = W_PERCENTAGE)
    i_plot = plot_data(dfa,
                [TOP_0_1, TOP_1, TOP_10, HIGH_MIDDLE_40, LOW_MIDDLE_40, BOTTOM_10, BOTTOM_1],
                xlabel = "Years",
                labels = ["Top 0.1%", "Top 1%", "Top 10%", "High Middle 40%", "Low Middle 40%", "Bottom 10%", "Bottom 1%"],
                type = I_PERCENTAGE)

    gini_plot = plot_gini_coefficients(dfa, xlabel = "Years")
    gini_rate_plot = plot_gini_rate(dfa, xlabel = "Years")

    if money_debt
        money_stock_plot = plot_stocks(dm, time_label = "Years")
        debt_stock_plot = plot_stocks(model_data, stock_symbol = :debt, stock_label = "Debt buildup",  time_label = "Years")
    else
        money_stock_plot = nothing
        debt_stock_plot = nothing
    end

    if taxes_expenses
        expenses_plot = plot_expenses(model_data)
        tax_brackets_plot = plot_tax_brackets(analyse_tax_brackets(model_data))
    else
        expenses_plot = nothing
        tax_brackets_plot = nothing
    end

    return YardSalePlots(w_plot,
                            i_plot,
                            gini_plot,
                            gini_rate_plot,
                            money_stock_plot,
                            debt_stock_plot,
                            expenses_plot,
                            tax_brackets_plot)
end

function plot_graphs_from_file(data_dir::String;
                                money_debt::Bool = true,
                                taxes_expenses::Bool = true)
    actor_data, model_data, dfa, dm = read_data(data_dir)
    plot_graphs(actor_data, model_data, dfa, dm,
                money_debt = money_debt,
                taxes_expenses = taxes_expenses)
end

function plot_graphs(actor_data::DataFrame,
                        model_data::DataFrame,
                        dfa::Dict{SimDataType, DataFrame},
                        dm::DataFrame;
                        money_debt::Bool = true,
                        taxes_expenses::Bool = true)
    yardsale_plots = create_plots(actor_data, model_data, dfa, dm,
                                    money_debt = money_debt,
                                    taxes_expenses = taxes_expenses)
    rows = 2 + (money_debt ? 1 : 0) + (taxes_expenses ? 1 : 0)
    ysize = rows * 400

    l = @layout [grid(rows, 2)]

    if money_debt && taxes_expenses
        plot(yardsale_plots.wealth,
                yardsale_plots.income,
                yardsale_plots.gini,
                yardsale_plots.gini_rate,
                yardsale_plots.money_stock,
                yardsale_plots.debt_stock,
                yardsale_plots.tax_brackets,
                yardsale_plots.expenses,
                layout = l,
            title = ["Wealth Inequality" "Income Inequality" "Gini Coefficients" "Gini Wealth / Income" "Money Stock" "Debt Buildup" "Tax Brackets" "Expenses vs Revenue"],
                titlefont = font(10),
                legend_font = font(6),
                xguidefont = font(8),
                yguidefont = font(8),
                xticksfont = font(4),
                yticksfont = font(4),
                size = (1200, ysize))
    elseif money_debt
        plot(yardsale_plots.wealth,
                yardsale_plots.income,
                yardsale_plots.gini,
                yardsale_plots.gini_rate,
                yardsale_plots.money_stock,
                yardsale_plots.debt_stock,
                layout = l,
            title = ["Wealth Inequality" "Income Inequality" "Gini Coefficients" "Gini Wealth / Income" "Money Stock" "Debt Buildup"],
                titlefont = font(10),
                legend_font = font(6),
                xguidefont = font(8),
                yguidefont = font(8),
                xticksfont = font(4),
                yticksfont = font(4),
                size = (1200, ysize))
    elseif taxes_expenses
        plot(yardsale_plots.wealth,
                yardsale_plots.income,
                yardsale_plots.gini,
                yardsale_plots.gini_rate,
                yardsale_plots.tax_brackets,
                yardsale_plots.expenses,
                layout = l,
            title = ["Wealth Inequality" "Income Inequality" "Gini Coefficients" "Gini Wealth / Income" "Tax Brackets" "Expenses vs Revenue"],
                titlefont = font(10),
                legend_font = font(6),
                xguidefont = font(8),
                yguidefont = font(8),
                xticksfont = font(4),
                yticksfont = font(4),
                size = (1200, ysize))
    else
        plot(yardsale_plots.wealth,
                yardsale_plots.income,
                yardsale_plots.gini,
                yardsale_plots.gini_rate,
                layout = l,
                title = ["Wealth Inequality" "Income Inequality" "Gini Coefficients" "Gini Wealth / Income"],
                titlefont = font(10),
                legend_font = font(6),
                xguidefont = font(8),
                yguidefont = font(8),
                xticksfont = font(4),
                yticksfont = font(4),
                size = (1200, ysize))
    end
end

function process_data(data::Tuple{DataFrame, DataFrame},
                        file_name::String;
                        money_debt::Bool = true,
                        taxes_expenses::Bool = true)
    dfa = analyse_data(data)
    dm = analyse_aggregate(data[1])

    write_data(file_name, data, dfa, dm)

    plot_graphs(data[1], data[2], dfa, dm,
                money_debt = money_debt,
                taxes_expenses = taxes_expenses)
end

# Plot funtions in paper order

function plot_c1_calibration(;country = BE, years = 100, run = false, zeta = ZETA)
    if run
        data = simulate_country(country,
                                sim_length = years * YEAR,
                                data_collection_interval = YEAR,
                                lock_random_generator = true,
                                num_actors = NUM_ACTORS,
                                monetary_type = M_FIXED,
                                population_type = P_FIXED,
                                gdp_growth_per_year = 0,
                                wealth_distribution = W_UNEQUAL,
                                wealth_transfer = 0.2,
                                wealth_accumulation_advantage = zeta,
                                gdp_scaling = 1,
                                taxes = T_INCOME_TAX,
                                deficit_spending = true,
                                cover_expenses = false,
                                scale_tax_to_target_revenue = true,
                                tax_interval = YEAR,
                                vat_active = true,
                                deduct_vat_from_taxes = true,
                                vat_interval = MONTH)
        return process_data(data, "c1")
    else
        return plot_graphs_from_file("c1",
                                    money_debt = false,
                                    taxes_expenses = false)
    end
end

function plot_b1_baseline(;country = BE, years = 30, run = false, zeta = ZETA)
    if run
        data = simulate_country(country,
                                sim_length = years * YEAR,
                                data_collection_interval = YEAR,
                                lock_random_generator = true,
                                num_actors = NUM_ACTORS,
                                monetary_type = M_FIXED,
                                population_type = P_FIXED,
                                gdp_growth_per_year = 0,
                                wealth_distribution = W_UNEQUAL,
                                wealth_transfer = 0.2,
                                wealth_accumulation_advantage = zeta,
                                gdp_scaling = 1,
                                taxes = T_NO_TAX,
                                cover_expenses = false,
                                deficit_spending = false,
                                scale_tax_to_target_revenue = false,
                                tax_interval = MONTH,
                                vat_active = false,
                                deduct_vat_from_taxes = false,
                                vat_interval = MONTH)
        return process_data(data, "b1",
                            money_debt = false,
                            taxes_expenses = false)
    else
        return plot_graphs_from_file("b1",
                                    money_debt = false,
                                    taxes_expenses = false)
    end
end

function plot_a1_ams_baseline(;country = BE, years = 100, run = false, zeta = ZETA)
    if run
        data = simulate_country(country,
                                sim_length = years * YEAR,
                                data_collection_interval = YEAR,
                                lock_random_generator = true,
                                num_actors = NUM_ACTORS,
                                monetary_type = M_SUMSY,
                                population_type = P_FIXED,
                                gdp_growth_per_year = 0,
                                wealth_distribution = W_UNEQUAL,
                                wealth_transfer = 0.2,
                                wealth_accumulation_advantage = zeta,
                                gdp_scaling = 1,
                                taxes = T_NO_TAX,
                                cover_expenses = false,
                                deficit_spending = false,
                                scale_tax_to_target_revenue = false,
                                tax_interval = MONTH,
                                vat_active = false,
                                deduct_vat_from_taxes = false,
                                vat_interval = MONTH)
        return process_data(data, "a1",
                            taxes_expenses = false)
    else
        return plot_graphs_from_file("a1",
                                    taxes_expenses = false)
    end
end

function plot_a2_ams_demtax(;country = BE, years = 100, run = false, zeta = ZETA)
    if run
        data = simulate_country(country,
                                sim_length = years * YEAR,
                                data_collection_interval = YEAR,
                                lock_random_generator = true,
                                num_actors = NUM_ACTORS,
                                monetary_type = M_SUMSY,
                                population_type = P_FIXED,
                                gdp_growth_per_year = 0,
                                wealth_distribution = W_UNEQUAL,
                                wealth_transfer = 0.2,
                                wealth_accumulation_advantage = zeta,
                                gdp_scaling = 1,
                                taxes = T_DEM_TAX,
                                cover_expenses = true,
                                deficit_spending = false,
                                scale_tax_to_target_revenue = false,
                                tax_interval = MONTH,
                                vat_active = false,
                                deduct_vat_from_taxes = false,
                                vat_interval = MONTH)
        return process_data(data, "a2")
    else
        return plot_graphs_from_file("a2")
    end
end

function plot_a3_ams_income_tax(;country = BE, years = 100, run = false, zeta = ZETA)
    if run
        data = simulate_country(country,
                                sim_length = years * YEAR,
                                data_collection_interval = YEAR,
                                lock_random_generator = true,
                                num_actors = NUM_ACTORS,
                                monetary_type = M_SUMSY,
                                population_type = P_FIXED,
                                gdp_growth_per_year = 0,
                                wealth_distribution = W_UNEQUAL,
                                wealth_transfer = 0.2,
                                wealth_accumulation_advantage = zeta,
                                gdp_scaling = 1,
                                taxes = T_INCOME_TAX,
                                cover_expenses = true,
                                deficit_spending = false,
                                scale_tax_to_target_revenue = true,
                                tax_interval = YEAR,
                                vat_active = false,
                                deduct_vat_from_taxes = false,
                                vat_interval = MONTH)
        return process_data(data, "a3")
    else
        return plot_graphs_from_file("a3")
    end
end

function plot_c2_income_tax(;country = BE, years = 100, run = false, zeta = ZETA)
    if run
        data = simulate_country(country,
                                sim_length = years * YEAR,
                                data_collection_interval = YEAR,
                                lock_random_generator = true,
                                num_actors = NUM_ACTORS,
                                monetary_type = M_FIXED,
                                population_type = P_FIXED,
                                gdp_growth_per_year = 0,
                                wealth_distribution = W_UNEQUAL,
                                wealth_transfer = 0.2,
                                wealth_accumulation_advantage = zeta,
                                gdp_scaling = 1,
                                taxes = T_INCOME_TAX,
                                cover_expenses = true,
                                deficit_spending = false,
                                scale_tax_to_target_revenue = true,
                                tax_interval = YEAR,
                                vat_active = false,
                                deduct_vat_from_taxes = false,
                                vat_interval = MONTH)
        return process_data(data, "c2")
    else
        return plot_graphs_from_file("c2")
    end
end

function plot_c3_declining_gdp_income_tax(;country = BE, years = 100, run = false, zeta = ZETA)
    if run
        data = simulate_country(country,
                                sim_length = years * YEAR,
                                data_collection_interval = YEAR,
                                lock_random_generator = true,
                                num_actors = NUM_ACTORS,
                                monetary_type = M_FIXED,
                                population_type = P_FIXED,
                                gdp_growth_per_year = -0.01,
                                wealth_distribution = W_UNEQUAL,
                                wealth_transfer = 0.2,
                                wealth_accumulation_advantage = zeta,
                                gdp_scaling = 1,
                                taxes = T_INCOME_TAX,
                                cover_expenses = true,
                                deficit_spending = false,
                                scale_tax_to_target_revenue = true,
                                tax_interval = YEAR,
                                vat_active = false,
                                deduct_vat_from_taxes = false,
                                vat_interval = MONTH)
        return process_data(data, "c3")
    else
        return plot_graphs_from_file("c3")
    end
end

function plot_a4_declining_gdp_demtax(;country = BE, years = 100, run = false, zeta = ZETA)
    if run
        data = simulate_country(country,
                                sim_length = years * YEAR,
                                data_collection_interval = YEAR,
                                lock_random_generator = true,
                                num_actors = NUM_ACTORS,
                                monetary_type = M_SUMSY,
                                population_type = P_FIXED,
                                gdp_growth_per_year = -0.01,
                                wealth_distribution = W_UNEQUAL,
                                wealth_transfer = 0.2,
                                wealth_accumulation_advantage = zeta,
                                gdp_scaling = 1,
                                taxes = T_DEM_TAX,
                                deficit_spending = false,
                                scale_tax_to_target_revenue = false,
                                tax_interval = MONTH,
                                vat_active = false,
                                deduct_vat_from_taxes = false,
                                vat_interval = MONTH)
        return process_data(data, "a4")
    else
        return plot_graphs_from_file("a4")
    end
end

function plot_a5_growing_gdp_demtax(;country = BE, years = 100, run = false, zeta = ZETA)
    if run
        data = simulate_country(country,
                            sim_length = years * YEAR,
                            data_collection_interval = YEAR,
                            lock_random_generator = true,
                            num_actors = NUM_ACTORS,
                            monetary_type = M_SUMSY,
                            population_type = P_FIXED,
                            gdp_growth_per_year = 0.01,
                            wealth_distribution = W_UNEQUAL,
                            wealth_transfer = 0.2,
                            wealth_accumulation_advantage = zeta,
                            gdp_scaling = 1,
                            taxes = T_DEM_TAX,
                            deficit_spending = false,
                            scale_tax_to_target_revenue = false,
                            tax_interval = MONTH,
                            vat_active = false,
                            deduct_vat_from_taxes = false,
                            vat_interval = MONTH)
        return process_data(data, "a5")
    else
        return plot_graphs_from_file("a5")
    end
end

function plot_c4_growing_gdp_income_tax(;country = BE, years = 100, run = false, zeta = ZETA)
    if run
        data = simulate_country(country,
                                sim_length = years * YEAR,
                                data_collection_interval = YEAR,
                                lock_random_generator = true,
                                num_actors = NUM_ACTORS,
                                monetary_type = M_FIXED,
                                population_type = P_FIXED,
                                gdp_growth_per_year = 0.01,
                                wealth_distribution = W_UNEQUAL,
                                wealth_transfer = 0.2,
                                wealth_accumulation_advantage = zeta,
                                gdp_scaling = 1,
                                taxes = T_INCOME_TAX,
                                cover_expenses = true,
                                deficit_spending = false,
                                scale_tax_to_target_revenue = true,
                                tax_interval = YEAR,
                                vat_active = false,
                                deduct_vat_from_taxes = false,
                                vat_interval = MONTH)
        return process_data(data, "c4")
    else
        return plot_graphs_from_file("c4")
    end
end

# Appendix simulations

function plot_a6_growing_gdp_demtax_vat(;country = BE, years = 100, run = false, zeta = ZETA)
    if run
        data = simulate_country(country,
                                sim_length = years * YEAR,
                                data_collection_interval = YEAR,
                                lock_random_generator = true,
                                num_actors = NUM_ACTORS,
                                monetary_type = M_SUMSY,
                                population_type = P_FIXED,
                                gdp_growth_per_year = 0.01,
                                wealth_distribution = W_UNEQUAL,
                                wealth_transfer = 0.2,
                                wealth_accumulation_advantage = zeta,
                                gdp_scaling = 1,
                                taxes = T_DEM_TAX,
                                deficit_spending = false,
                                scale_tax_to_target_revenue = false,
                                tax_interval = MONTH,
                                vat_active = true,
                                deduct_vat_from_taxes = true,
                                vat_interval = MONTH)
        return process_data(data, "a6",
                            money_debt = false,
                            taxes_expenses = false)
    else
        return plot_graphs_from_file("a6",
                                    money_debt = false,
                                    taxes_expenses = false)
    end
end

function plot_a7_growing_gdp_demtax_vat_no_deduction(;country = BE, years = 100, run = false, zeta = ZETA)
    if run
        data = simulate_country(country,
                                sim_length = years * YEAR,
                                data_collection_interval = YEAR,
                                lock_random_generator = true,
                                num_actors = NUM_ACTORS,
                                monetary_type = M_SUMSY,
                                population_type = P_FIXED,
                                gdp_growth_per_year = 0.01,
                                wealth_distribution = W_UNEQUAL,
                                wealth_transfer = 0.2,
                                wealth_accumulation_advantage = zeta,
                                gdp_scaling = 1,
                                taxes = T_DEM_TAX,
                                deficit_spending = false,
                                scale_tax_to_target_revenue = false,
                                tax_interval = MONTH,
                                vat_active = true,
                                deduct_vat_from_taxes = false,
                                vat_interval = MONTH)
        return process_data(data, "a7",
                            money_debt = false,
                            taxes_expenses = false)
    else
        return plot_graphs_from_file("a7",
                                    money_debt = false,
                                    taxes_expenses = false)
    end
end

function plot_a8_growing_gdp_income_tax(;country = BE, years = 100, run = false, zeta = ZETA)
    if run
        data = simulate_country(country,
                                sim_length = years * YEAR,
                                data_collection_interval = YEAR,
                                lock_random_generator = true,
                                num_actors = NUM_ACTORS,
                                monetary_type = M_SUMSY,
                                population_type = P_FIXED,
                                gdp_growth_per_year = 0.01,
                                wealth_distribution = W_UNEQUAL,
                                wealth_transfer = 0.2,
                                wealth_accumulation_advantage = zeta,
                                gdp_scaling = 1,
                                taxes = T_INCOME_TAX,
                                deficit_spending = false,
                                scale_tax_to_target_revenue = true,
                                tax_interval = YEAR,
                                vat_active = false,
                                deduct_vat_from_taxes = false,
                                vat_interval = MONTH)
        return process_data(data, "a8",
                            money_debt = false,
                            taxes_expenses = false)
    else
        return plot_graphs_from_file("a8",
                                    money_debt = false,
                                    taxes_expenses = false)
    end
end

function plot_u1_flat_tax_funded_ubi(;country = BE, years = 100, run = false, zeta = ZETA)
    if run
        data = simulate_country(country,
                                sim_length = years * YEAR,
                                data_collection_interval = YEAR,
                                lock_random_generator = true,
                                num_actors = NUM_ACTORS,
                                monetary_type = M_FIXED,
                                population_type = P_FIXED,
                                gdp_growth_per_year = 0,
                                wealth_distribution = W_UNEQUAL,
                                wealth_transfer = 0.2,
                                wealth_accumulation_advantage = zeta,
                                gdp_scaling = 1,
                                taxes = T_GDP_FLAT_TAX,
                                deficit_spending = false,
                                scale_tax_to_target_revenue = false,
                                tax_interval = MONTH,
                                vat_active = false,
                                deduct_vat_from_taxes = false,
                                vat_interval = MONTH)
        return process_data(data, "u1",
                            money_debt = false,
                            taxes_expenses = false)
    else
        return plot_graphs_from_file("u1",
                                    money_debt = false,
                                    taxes_expenses = false)
    end
end

function plot_a9_ams_income_tax_high_zeta(;country = BE, years = 100, run = false, zeta = 0.5)
    if run
        data = simulate_country(country,
                                sim_length = years * YEAR,
                                data_collection_interval = YEAR,
                                lock_random_generator = true,
                                num_actors = NUM_ACTORS,
                                monetary_type = M_SUMSY,
                                population_type = P_FIXED,
                                gdp_growth_per_year = 0,
                                wealth_distribution = W_UNEQUAL,
                                wealth_transfer = 0.2,
                                wealth_accumulation_advantage = zeta,
                                gdp_scaling = 1,
                                taxes = T_INCOME_TAX,
                                deficit_spending = false,
                                scale_tax_to_target_revenue = true,
                                tax_interval = YEAR,
                                vat_active = false,
                                deduct_vat_from_taxes = false,
                                vat_interval = MONTH)
        return process_data(data, "a9",
                            money_debt = false,
                            taxes_expenses = false)
    else
        return plot_graphs_from_file("a9",
                                    money_debt = false,
                                    taxes_expenses = false)
    end
end

function plot_c5_income_tax_high_zeta(;country = BE, years = 100, run = false, zeta = 0.5)
    if run
        data = simulate_country(country,
                                sim_length = years * YEAR,
                                data_collection_interval = YEAR,
                                lock_random_generator = true,
                                num_actors = NUM_ACTORS,
                                monetary_type = M_FIXED,
                                population_type = P_FIXED,
                                gdp_growth_per_year = 0,
                                wealth_distribution = W_UNEQUAL,
                                wealth_transfer = 0.2,
                                wealth_accumulation_advantage = zeta,
                                gdp_scaling = 1,
                                taxes = T_INCOME_TAX,
                                cover_expenses = true,
                                deficit_spending = false,
                                scale_tax_to_target_revenue = true,
                                tax_interval = YEAR,
                                vat_active = false,
                                deduct_vat_from_taxes = false,
                                vat_interval = MONTH)
        return process_data(data, "c5",
                            money_debt = false,
                            taxes_expenses = false)
    else
        return plot_graphs_from_file("c5",
                                    money_debt = false,
                                    taxes_expenses = false)
    end
end

function plot_a10_ams_demtax_high_zeta(;country = BE, years = 100, run = false, zeta = 0.5)
    if run
        data = simulate_country(country,
                                sim_length = years * YEAR,
                                data_collection_interval = YEAR,
                                lock_random_generator = true,
                                num_actors = NUM_ACTORS,
                                monetary_type = M_SUMSY,
                                population_type = P_FIXED,
                                gdp_growth_per_year = 0,
                                wealth_distribution = W_UNEQUAL,
                                wealth_transfer = 0.2,
                                wealth_accumulation_advantage = zeta,
                                gdp_scaling = 1,
                                taxes = T_DEM_TAX,
                                deficit_spending = false,
                                scale_tax_to_target_revenue = true,
                                tax_interval = YEAR,
                                vat_active = false,
                                deduct_vat_from_taxes = false,
                                vat_interval = MONTH)
        return process_data(data, "a10",
                            money_debt = false,
                            taxes_expenses = false)
    else
        return plot_graphs_from_file("a10",
                                    money_debt = false,
                                    taxes_expenses = false)
    end
end