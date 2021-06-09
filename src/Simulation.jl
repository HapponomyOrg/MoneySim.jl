using EconoSim # EconoSim 0.1.2 or https://github.com/HapponomyOrg/EconoSim.jl
using Plots
using CSV

"""
    Mode in which the simulation is run.
* fixed_growth: growth ratio and profit ratio is fixed.
* random_growth: growth ratio is random, profit ratio is relative to growth ratio.
* fixed loan ratio: loan ratio and profit ratio is fixed.
"""
@enum Mode fixed_growth random_growth fixed_loan_ratio

RealFunc = Union{Real, Function}

value(rf::RealFunc) = rf isa Function ? rf() : rf

struct SimData
    growth_ratio::Vector{Fixed(4)}
    profit_ratio::Vector{Fixed(4)}
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
required_loan_ratio(data::SimData) = ./(100 * data.required_loan, money_stock(data))
growth_ratio(data::SimData) = .*(data.growth_ratio, 100)
profit_ratio(data::SimData) = .*(data.profit_ratio, 100)

function Base.resize!(data::SimData, size::Integer)
    if size != length(data)
        for field in fieldnames(SimData)
            resize!(getfield(data, field), size)
        end
    end

    return data
end

function process_cycle!(cycle::Integer,
                    data::SimData,
                    mode::Mode,
                    mode_ratio::RealFunc,
                    loans::Vector{Debt},
                    profit_ratio::Real,
                    save_ratio::Real,
                    maturity::Integer,
                    loan_satisfaction::Real)
    money_stock = current_money_stock()
    mode_ratio = value(mode_ratio)

    # process loans
    for loan in loans
        process_debt!(loan)
    end

    data.installment[cycle] = money_stock - current_money_stock()

    # Only the first loan can have reached maturity
    if !isempty(loans) && debt_settled(loans[1])
        deleteat!(loans, 1)
    end

    # determine required and real loan
    if mode != fixed_loan_ratio
        target_money_stock = (1 + mode_ratio) * money_stock
        data.required_loan[cycle] = max(0, target_money_stock - current_money_stock())

        if mode == random_growth
            if cycle == 1
                profit_ratio = 0
            else
                profit_ratio = mode_ratio + profit_ratio
            end
        end
    else
        data.required_loan[cycle] = max(0, (money_stock - data.installment[cycle]) / (1 - mode_ratio) * mode_ratio)
    end

    data.loan[cycle] = data.required_loan[cycle] * loan_satisfaction

    if data.loan[cycle] > 0
        push!(loans, bank_loan(bank, available, data.loan[cycle], profit_ratio, maturity))
    end

    # save money if available
    transfer_asset!(available, saved, DEPOSIT, max(0, current_available() * save_ratio))

    data.growth_ratio[cycle] = Fixed(4)((current_money_stock() - money_stock)) / money_stock
    data.profit_ratio[cycle] = mode_ratio
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
                    bank_profit_rate::RealFunc,
                    save_ratio::Real,
                    maturity::Integer,
                    cycles::Integer;
                    loan_satisfaction::Real = 1)

# Arguments
* mode::Mode - The simulation mode.
* mode_ratio::RealFunc - Either the growth factor of the money stock or the loan rate per cycle.
* money_stock::Real - The initial money stock.
* debt_ratio::Real - The initial debt ratio.
* profit_ratio::Real - The net bank profit rate on bank debt per cycle.
* save_ratio::Real - The percentage of money stock which is saved each cycle. This money is not available to pay off debt with. Saved money is part of the money stock.
* maturity::Integer - The maturity of the loans.
* cycles::Integer - The number of cycles the simulation runs.
* loan_satisfaction::Real - The satisfaction rate of the required loan.
"""
function simulate_banks(mode::Mode,
                mode_ratio::RealFunc,
                money_stock::Real,
                debt_ratio::Real,
                profit_ratio::Real,
                save_ratio::Real,
                maturity::Integer,
                cycles::Integer;
                loan_satisfaction::Real = 1)
    money_stock = Currency(money_stock)
    debt = money_stock * debt_ratio # determine debt

    # reset balance sheets
    clear!(bank)
    clear!(available)
    clear!(saved)

    loans = Vector{Debt}()

    if mode == random_growth
        push!(loans, bank_loan(bank, available, debt, 0, maturity)) # set profit ratio for initial debt to 0
    else
        push!(loans, bank_loan(bank, available, debt, 0, maturity)) # create initial debt
    end

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

function plot_required_loan_ratio(data::SimData)
    series = required_loan_ratio(data)
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

function plot_money_stock(data::SimData)
    series = money_stock(data)
    plot(series, label = "M", title = "Money stock (" * string(length(data)) * " years)")
    xaxis!("Years")

    return yaxis!("Stock")
end

function plot_data(mode::Mode, m::RealFunc, p::Real, s::Real, maturity::Integer, cycles::Integer = 100)
    data = simulate_banks(mode, m, 1000000, 1, p, s, maturity, cycles)
    m = m isa Function ? m : Fixed(4)(m * 100)
    p = Fixed(4)(p * 100)
    s = Fixed(4)(s * 100)

    if mode != fixed_loan_ratio
        plot_required_loan_ratio(data)
        savefig("plots/" * string(mode) * "_LR_growth_" * string(m) * "_profit_" * string(p) * "_save_" * string(s) * "_" * string(maturity) * "_" * string(cycles) * ".png")
        plot_debt_ratio(data)
        savefig("plots/" * string(mode) * "_DR_growth_" * string(m) * "_profit_" * string(p) * "_save_" * string(s) * "_" * string(maturity) * "_" * string(cycles) * ".png")

        if mode == random_growth
            plot_growth_ratio(data)
            savefig("plots/" * string(mode) * "_g_growth_" * string(m) * "_profit_" * string(p) * "_save_" * string(s) * "_" * string(maturity) * "_" * string(cycles) * ".png")
        end

        return last(required_loan_ratio(data)), last(debt_ratio(data))
    else
        plot_growth_ratio(data)
        savefig("plots/" * string(mode) * "_g_LR_" * string(m) * "_profit_" * string(p) * "_save_" * string(s) * "_" * string(maturity) * "_" * string(cycles) * ".png")
        plot_money_stock(data)
        savefig("plots/" * string(mode) * "_M_LR_" * string(m) * "_profit_" * string(p) * "_save_" * string(s) * "_" * string(maturity) * "_" * string(cycles) * ".png")
        plot_debt_ratio(data)
        savefig("plots/" * string(mode) * "_DR_LR_" * string(m) * "_profit_" * string(p) * "_save_" * string(s) * "_" * string(maturity) * "_" * string(cycles) * ".png")

        return last(growth_ratio(data)), last(debt_ratio(data))
    end
end

function get_random_growth(low, high)
    return rand() * (high - low) + low
end

function simulations()
    for maturity = 10:10:20
        # No proft, no savings
        plot_data(fixed_growth, 0, 0, 0, maturity)

        plot_data(fixed_growth, 0.01, 0, 0, maturity)

        # Profit, no savings
        plot_data(fixed_growth, 0.05, 0.01, 0, maturity)

        plot_data(fixed_growth, 0.05, 0.01, 0, maturity, 500)

        plot_data(fixed_growth, 0.05, 0.05, 0, maturity)
        plot_data(fixed_growth, 0.05, 0.1, 0, maturity)

        plot_data(fixed_growth, 0.05, 0.006, 0, maturity, 500)

        plot_data(fixed_growth, 0.0484, 0.006, 0, maturity, 500)

        plot_data(fixed_growth, 0.05, 0.007, 0, maturity, 500)

        plot_data(fixed_loan_rate, 0.15, 0.006, 0, maturity, 500)
        plot_data(fixed_loan_rate, 0.15, 0.00577, 0, maturity, 500)
        plot_data(fixed_loan_rate, 0.15, 0.007, 0, maturity, 500)

        plot_data(fixed_loan_rate, 0.15, 0.01, 0, maturity, 500)
        plot_data(fixed_loan_rate, 0.149, 0.01, 0, maturity, 500)
        plot_data(fixed_loan_rate, 0.14, 0.01, 0, maturity, 500)
        plot_data(fixed_loan_rate, 0.15, 0.011, 0, maturity, 500)
        plot_data(fixed_loan_rate, 0.15, 0.012, 0, maturity, 500)
        plot_data(fixed_loan_rate, 0.15, 0.013, 0, maturity, 500)
        plot_data(fixed_loan_rate, 0.15, 0.02, 0, maturity, 500)
    end
end

function random_simulations()
    grow_func() = get_random_growth(0.02, 0.12)

    plot_data(random_growth, grow_func, -0.05, 0, 20, 500)
    plot_data(random_growth, grow_func, 0, 0, 20, 500)
    plot_data(random_growth, grow_func, 0.05, 0, 20, 500)
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
