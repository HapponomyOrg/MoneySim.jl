using EconoSim # EconoSim 0.1.2 or https://github.com/HapponomyOrg/EconoSim.jl
using Plots
using CSV

"""
    Mode in which the simulation is run.
* growth_mode: growth ratio and profit ratio is fixed.
* loan_ratio_mode: growth ratio is random, profit ratio is relative to growth ratio.
* fixed loan ratio: loan ratio and profit ratio is fixed.
"""
@enum Mode growth_mode loan_ratio_mode

RealFunc = Union{Real, Function}
value(rf::RealFunc) = rf isa Function ? rf() : rf

IntFunc = Union{Integer, Function}
value(intf::IntFunc) = intf isa Function ? intf() : intf

struct SimData
    growth_ratio::Vector{Fixed(4)}
    profit_ratio::Vector{Fixed(4)}
    maturity::Vector{Int32}
    qe_adjustment::Vector{Currency}
    available::Vector{Currency}
    saved::Vector{Currency}
    debt::Vector{Currency}
    installment::Vector{Currency}
    required_loan::Vector{Currency}
    loan::Vector{Currency}
    bank_equity::Vector{Currency}
    SimData(size::Integer) = new(Vector{Fixed(4)}(undef, size),
                                Vector{Fixed(4)}(undef, size),
                                Vector{Int32}(undef, size),
                                Vector{Currency}(undef, size),
                                Vector{Currency}(undef, size),
                                Vector{Currency}(undef, size),
                                Vector{Currency}(undef, size),
                                Vector{Currency}(undef, size),
                                Vector{Currency}(undef, size),
                                Vector{Currency}(undef, size),
                                Vector{Currency}(undef, size))
end

Base.length(data::SimData) = length(data.growth_ratio)

# agregate bank balance sheet
bank = Balance(def_min_asset = typemin(Currency), log_transactions = false)
# aggregate balance for money available to pay off debt
available = Balance(def_min_asset = typemin(Currency), log_transactions = false)
# aggregate balance to save money not available to pay off debt
saved = Balance(def_min_asset = typemin(Currency), log_transactions = false)

current_available() = asset_value(available, DEPOSIT)
current_saved() = asset_value(saved, DEPOSIT)
current_money_stock() = current_available() + current_saved()

money_stock(data::SimData) = .+(data.available, data.saved)
debt_ratio(data::SimData) = ./(100 * data.debt, money_stock(data))
loan_ratio(data::SimData) = ./(100 * data.loan, money_stock(data))
growth_ratio(data::SimData) = .*(data.growth_ratio, 100)
profit_ratio(data::SimData) = .*(data.profit_ratio, 100)
delta_growth_profit(data::SimData) = .-(100 * data.growth_ratio, 100 * data.profit_ratio)

function Base.resize!(data::SimData, size::Integer)
    if size != length(data)
        for field in fieldnames(SimData)
            resize!(getfield(data, field), size)
        end
    end

    return data
end

"""
    process_cycle!(cycle::Integer,
                    data::SimData,
                    mode::Mode,
                    mode_ratio::RealFunc,
                    loans::Vector{Debt},
                    profit_ratio::Real,
                    relative_profit::Bool,
                    save_ratio::Real,
                    maturity::IntFunc,
                    loan_satisfaction::Real)

# Arguments
* cycle::Integer - the current cycle.
* data::SimData - struct for collecting data.
* mode::Mode - mode in which the simulation is running. Either growth_mode or loan_ratio_mode.
* mode_ratio::RealFunc - a value or function determining the value for the leading variable for the simulation. Either growth ratio or loan ratio.
* loans::Vector{Debt} - the collection of all active loans.
* profit_ratio::Real - the profit ratio on loans for this cycle.
* relative_profit::Bool - whether or not profit ratio is relative to growth ratio. If it is true this value is added to the growth ratio of the cycle to determine real profit ratio for the current cycle.
* save_ratio::Real - the ratio at which money is saved.
* maturity::IntFunc - the function or value determining loan maturity for this cycle.
* loan_satisfaction::Real - determines the actual loan demand.
"""
function process_cycle!(cycle::Integer,
                    data::SimData,
                    mode::Mode,
                    mode_ratio::RealFunc,
                    loans::Vector{Debt},
                    profit_ratio::Real,
                    relative_profit::Bool,
                    save_ratio::Real,
                    maturity::IntFunc,
                    loan_satisfaction::Real)
    money_stock = current_money_stock()
    mode_ratio = value(mode_ratio)
    maturity = value(maturity)

    # process loans
    settled_loan_indices = Vector{Integer}()
    index = 1

    for loan in loans
        process_debt!(loan)

        if debt_settled(loan)
            # Store the index
            push!(settled_loan_indices, index)
        end

        index += 1
    end

    # Delete all settled loans
    for index in reverse(settled_loan_indices)
        deleteat!(loans, index)
    end

    data.installment[cycle] = money_stock - current_money_stock()

    # determine required and real loan
    if mode == growth_mode
        target_money_stock = (1 + mode_ratio) * money_stock
        # There can not be negative loans
        data.required_loan[cycle] = round(max(0, target_money_stock - current_money_stock()), digits = 2)
    else # loan_ratio mode
        data.required_loan[cycle] = round(max(0, (money_stock - data.installment[cycle]) / (1 - mode_ratio) * mode_ratio), digits = 2)
    end

    data.loan[cycle] = data.required_loan[cycle] * loan_satisfaction
    # Predict growth
    data.growth_ratio[cycle] = Fixed(4)((current_money_stock() - money_stock + data.loan[cycle])) / money_stock

    if data.loan[cycle] > 0
        if relative_profit
            profit_ratio = data.growth_ratio[cycle] + profit_ratio
        end

        data.profit_ratio[cycle] = profit_ratio
        push!(loans, bank_loan(bank, available, data.loan[cycle], profit_ratio, maturity))
    end

    # save money if available
    transfer_asset!(available, saved, DEPOSIT, max(0, current_available() * save_ratio))

    data.available[cycle] = current_available()
    data.saved[cycle] = current_saved()
    data.debt[cycle] = asset_value(bank, DEBT)
    data.bank_equity[cycle] = liability_value(bank, EQUITY)
end

"""
    simulate_banks(mode::Mode,
                    mode_ratio::RealFunc,
                    money_stock::Real,
                    debt_ratio::Real,
                    profit_ratio::RealFunc,
                    relative_profit::Bool,
                    save_ratio::Real,
                    maturity::IntFunc,
                    cycles::Integer;
                    loan_satisfaction::Real = 1)

# Arguments
* mode::Mode - The simulation mode.
* mode_ratio::RealFunc - Either the growth factor of the money stock or the loan ratio per cycle.
* money_stock::Real - The initial money stock.
* debt_ratio::Real - The initial debt ratio.
* profit_ratio::Real - The net bank profit rate on bank debt per cycle.
* relative_profit::Bool : whether or not profit ratio is relative to growth ratio. If it is true this value is added to the growth ratio of each cycle to determine real profit ratio for that cycle.
* save_ratio::Real - The percentage of money stock which is saved each cycle. This money is not available to pay off debt with. Saved money is part of the money stock.
* maturity::IntFunc - The maturity of the loans.
* cycles::Integer - The number of cycles the simulation runs.
* loan_satisfaction::Real - The satisfaction rate of the required loan.
"""
function simulate_banks(mode::Mode,
                mode_ratio::RealFunc,
                money_stock::Real,
                debt_ratio::Real,
                profit_ratio::Real,
                relative_profit::Bool,
                save_ratio::Real,
                maturity::IntFunc,
                cycles::Integer;
                loan_satisfaction::Real = 1)
    money_stock = Currency(money_stock)
    debt = money_stock * debt_ratio # determine debt

    # reset balance sheets
    clear!(bank)
    clear!(available)
    clear!(saved)

    loans = Vector{Debt}()

    push!(loans, bank_loan(bank, available, debt, 0, value(maturity))) # set profit ratio for initial debt to 0

    # Adjust for debt ratio's different from 100%
    book_asset!(available, DEPOSIT, money_stock - debt)
    book_liability!(bank, DEPOSIT, money_stock - debt)

    data = SimData(cycles)

    num_cycles = cycles

    # run simulation
    for cycle in 1:cycles
        process_cycle!(cycle,
                        data,
                        mode,
                        mode_ratio,
                        loans,
                        profit_ratio,
                        relative_profit,
                        save_ratio,
                        maturity,
                        loan_satisfaction)

        if current_available() + current_saved() <= 0
            num_cycles = cycle - 1
            break
        end
    end

    return resize!(data, num_cycles)
end

function plot_maturity(data::SimData)
    series = data.maturity
    plot(series, label = "m", title = "Maturity (" * string(length(data)) * " years)")
    xaxis!("Years")

    return yaxis!("Maturity")
end

function plot_loan_ratio(data::SimData)
    series = loan_ratio(data)
    plot(series, label = "LR", title = "Loan ratio (" * string(length(data)) * " years)")
    xaxis!("Years")

    return yaxis!("Percentage")
end

function plot_debt_ratio(data::SimData)
    series = debt_ratio(data)
    plot(series, label = "DR", title = "Debt ratio (" * string(length(data)) * " years)")
    xaxis!("Years")

    return yaxis!("Percentage")
end

function plot_growth_ratio(data::SimData)
    series = growth_ratio(data)
    plot(series, label = "g", title = "Growth ratio (" * string(length(data)) * " years)")
    xaxis!("Years")

    return yaxis!("Percentage")
end

function plot_profit_ratio(data::SimData)
    series = profit_ratio(data)
    plot(series, label = "p", title = "Profit ratio (" * string(length(data)) * " years)")
    xaxis!("Years")

    return yaxis!("Percentage")
end

function plot_delta_growth_profit(data::SimData)
    series = delta_growth_profit(data)
    plot(series, label = "g - p", title = "Growth - Profit (" * string(length(data)) * " years)")
    xaxis!("Years")

    return yaxis!("g - p")
end

function plot_money_stock(data::SimData)
    series = money_stock(data)
    plot(series, label = "M", title = "Money stock (" * string(length(data)) * " years)")
    xaxis!("Years")

    return yaxis!("Stock")
end

function plot_D_over_L(data::SimData)
    series = ./(data.debt, data.loan)
    g = last(data.growth_ratio)
    p = last(data.profit_ratio)
    LR = Fixed(4)(100 * last(data.loan) / last(money_stock(data))) / 100
    parameter_str = "g = " * string(g) * " p = " * string(p) * " LR = " * string(LR)
    plot(series, label = "D/L", title = parameter_str * " (" * string(length(data)) * " years)")
    xaxis!("Years")

    return yaxis!("D/L")
end

function plot_data(mode::Mode, m::RealFunc, p::Real, relative_p::Bool, s::Real, maturity::RealFunc, cycles::Integer = 100)
    data = simulate_banks(mode, m, 1000000, 1, p, relative_p, s, maturity, cycles)
    m = m isa Function ? m : Fixed(4)(m * 100)
    p = Fixed(4)(p * 100)
    s = Fixed(4)(s * 100)

    if mode == growth_mode
        plot_loan_ratio(data)
        savefig("plots/" * string(mode) * "_LR_growth_" * string(m) * "_profit_" * string(p) * "_save_" * string(s) * "_" * string(maturity) * "_" * string(cycles) * ".png")
        plot_debt_ratio(data)
        savefig("plots/" * string(mode) * "_DR_growth_" * string(m) * "_profit_" * string(p) * "_save_" * string(s) * "_" * string(maturity) * "_" * string(cycles) * ".png")

        if mode == loan_ratio_mode
            plot_growth_ratio(data)
            savefig("plots/" * string(mode) * "_g_growth_" * string(m) * "_profit_" * string(p) * "_save_" * string(s) * "_" * string(maturity) * "_" * string(cycles) * ".png")
        end

        return last(loan_ratio(data)), last(debt_ratio(data))
    else
        plot_growth_ratio(data)
        savefig("plots/" * string(mode) * "_g_LR_" * string(m) * "_profit_" * string(p) * "_save_" * string(s) * "_" * string(maturity) * "_" * string(cycles) * ".png")
        plot_money_stock(data)
        savefig("plots/" * string(mode) * "_M_LR_" * string(m) * "_profit_" * string(p) * "_save_" * string(s) * "_" * string(maturity) * "_" * string(cycles) * ".png")
        plot_debt_ratio(data)
        savefig("plots/" * string(mode) * "_DR_LR_" * string(m) * "_profit_" * string(p) * "_save_" * string(s) * "_" * string(maturity) * "_" * string(cycles) * ".png")
        plot_delta_growth_profit(data)
        savefig("plots/" * string(mode) * "_g-p_LR_" * string(m) * "_profit_" * string(p) * "_save_" * string(s) * "_" * string(maturity) * "_" * string(cycles) * ".png")

        return last(growth_ratio(data)), last(debt_ratio(data))
    end
end

function simulations()
    maturity = 20

    # No proft, no savings
    plot_data(growth_mode, 0, 0, false, 0, maturity)
    plot_data(growth_mode, 0.01, 0, false, 0, maturity)

    # Profit, no savings, p < g
    plot_data(growth_mode, 0.05, 0.01, false, 0, maturity)
    plot_data(growth_mode, 0.05, 0.01, false, 0, maturity, 500)

    # Profit, no savings, p >= g
    plot_data(growth_mode, 0.05, 0.05, false, 0, maturity)
    plot_data(growth_mode, 0.05, 0.1, false, 0, maturity)

    plot_data(growth_mode, 0.0475, 0.008, false, 0, maturity, 500)

    plot_data(loan_ratio_mode, 0.15, 0.008, false, 0, maturity, 500)
    plot_data(loan_ratio_mode, 0.15, 0.009, false, 0, maturity, 500)
    plot_data(loan_ratio_mode, 0.149, 0.008, false, 0, maturity, 500)
    plot_data(loan_ratio_mode, 0.149, 0.008, false, 0, 30, 500)
end

random_float(low::Real, high::Real) = rand() * (high - low) + low
random_int(low::Integer, high::Integer) = rand(low:high)

function random_simulations()
    grow_func() = random_float(0.02, 0.12)

    plot_data(growth_mode, grow_func, -0.05, true, 0, 20, 100)
    plot_data(growth_mode, grow_func, 0, true, 0, 20, 100)
    plot_data(growth_mode, grow_func, 0.05, true, 0, 20, 100)

    loan_func() = random_float(0.01, 0.2)
    maturity_func() = random_int(1, 30)
    plot_data(loan_ratio_mode, loan_func, -0.001, true, 0, maturity_func, 500)
    plot_data(loan_ratio_mode, loan_func, -0.05, true, 0, maturity_func, 500)
    plot_data(loan_ratio_mode, loan_func, 0, true, 0, maturity_func, 500)
    plot_data(loan_ratio_mode, loan_func, 0.05, true, 0, maturity_func, 500)
end

function convenience_plots()
    g = 0.05
    p = 0.01
    m = 20
    data = simulate_banks(growth_mode, g, 1000000, 1, p, false, 0, m, 500)
    LR = Fixed(4)(100 * last(data.loan) / last(money_stock(data))) / 100

    plot_D_over_L(data)

    data = simulate_banks(loan_ratio_mode, LR, 1000000, 1, p, false, 0, m, 500)
    plot_D_over_L(data)
    plot_growth_ratio(data)
end

function process_csv(csv_file::String)
    csv_data = CSV.File(csv_file)
    data = Vector([Vector{Real}(), Vector{Real}()])

    cur_row = 1

    for row in csv_data
        cur_col = 1

        for column in row
            append!(data[cur_col], column)
            cur_col += 1
        end

        cur_row += 1
    end

    return data
end
