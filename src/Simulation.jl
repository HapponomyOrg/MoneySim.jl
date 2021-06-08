using EconoSim # EconoSim 0.1.2 or https://github.com/HapponomyOrg/EconoSim.jl
using Plots
using CSV

@enum Mode fixed_growth fixed_loan_rate

struct SimData
    growth::Vector{Fixed(4)}
    qe_adjustment::Vector{Currency}
    available::Vector{Currency}
    saved::Vector{Currency}
    debt::Vector{Currency}
    installment::Vector{Currency}
    required_loan::Vector{Currency}
    loan::Vector{Currency}
    bank_equity::Vector{Currency}
    SimData(size::Integer) = new(Vector{Fixed(4)}(undef, size),
                                Vector{Currency}(undef, size),
                                Vector{Currency}(undef, size),
                                Vector{Currency}(undef, size),
                                Vector{Currency}(undef, size),
                                Vector{Currency}(undef, size),
                                Vector{Currency}(undef, size),
                                Vector{Currency}(undef, size),
                                Vector{Currency}(undef, size))
end

Base.length(data::SimData) = length(data.growth)

# agregate bank balance sheet
bank = Balance(def_min_asset = typemin(Currency), log_transactions = false)
# aggregate balance for money available to pay off debt
available = Balance(def_min_asset = typemin(Currency), log_transactions = false)
# aggregate balance to save money not available to pay off debt
saved = Balance(def_min_asset = typemin(Currency), log_transactions = false)

current_available() = asset_value(available, DEPOSIT)
current_saved() = asset_value(saved, DEPOSIT)
current_money_stock() = current_available() + current_saved()

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
                    mode_ratio::Real,
                    loans::Vector{Debt},
                    bank_profit_rate::Real,
                    save_ratio::Real,
                    maturity::Integer,
                    loan_satisfaction::Real)
    money_stock = current_money_stock()

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
    if mode == fixed_growth
        target_money_stock = (1 + mode_ratio) * money_stock
        data.required_loan[cycle] = max(0, target_money_stock - current_money_stock())
    else
        data.required_loan[cycle] = max(0, (money_stock - data.installment[cycle]) / (1 - mode_ratio) * mode_ratio)
    end

    data.loan[cycle] = data.required_loan[cycle] * loan_satisfaction

    if data.loan[cycle] > 0
        push!(loans, bank_loan(bank, available, data.loan[cycle], bank_profit_rate, maturity))
    end

    # save money if available
    transfer_asset!(available, saved, DEPOSIT, max(0, current_available() * save_ratio))

    data.growth[cycle] = Fixed(4)((current_money_stock() - money_stock)) / money_stock
    data.available[cycle] = current_available()
    data.saved[cycle] = current_saved()
    data.debt[cycle] = asset_value(bank, DEBT)
    data.bank_equity[cycle] = liability_value(bank, EQUITY)
end

"""
    simulate_banks(mode::Mode,
                    mode_ratio::Real,
                    money_stock::Real,
                    debt_ratio::Real,
                    bank_profit_rate::Real,
                    save_ratio::Real,
                    maturity::Integer,
                    cycles::Integer;
                    loan_satisfaction::Real = 1)

# Arguments
* mode::Mode - The simulation mode.
* mode_ratio::Real - Either the growth factor of the money stock or the koan rate per cycle.
* money_stock::Real - The initial money stock.
* debt_ratio::Real - The initial debt ratio.
* bank_profit_rate::Real - The net bank profit rate on bank debt per cycle.
* save_ratio::Real - The percentage of money stock which is saved each cycle. This money is not available to pay off debt with. Saved money is part of the money stock.
* maturity::Integer - The maturity of the loans.
* cycles::Integer - The number of cycles the simulation runs.
* loan_satisfaction::Real - The satisfaction rate of the required loan.
"""
function simulate_banks(mode::Mode,
                mode_ratio::Real,
                money_stock::Real,
                debt_ratio::Real,
                bank_profit_rate::Real,
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
    push!(loans, bank_loan(bank, available, debt, bank_profit_rate, maturity)) # create initial debt

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
                        bank_profit_rate,
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

function process_data(money_stock::Vector{Real},
                    debt::Vector{Real},
                    savings::Vector{Real},
                    qe::Vector{Real})
    money_stock = Vector{Currency}(money_stock)
    debt = Vector{Currency}(debt)
    savings = Vector{Currency}(savings)
    qe = Vector{Currency}(qe)

    data = SimData(length(money_stock))
    data.saved[1] = savings[1]
    data.available[1] = money_stock[1] - savings[1]
    data.debt[1] = debt[1]
    data.qe_adjustment[1] = qe[1]
    data.bank_equity[1] = debt[1] - money_stock[1]

    for cycle in 2:length(money_stock)
        data.growth[cycle] = (money_stock[cycle] - money_stock[cycle - 1]) / money_stock[cycle - 1]
        data.saved[cycle] = savings[cycle]
        data.available[cycle] = money_stock[cycle] - savings[cycle]
        data.debt[cycle] = debt[cycle]
        data.qe_adjustment[cycle] = data.qe_adjustment[cycle - 1] + qe[cycle]
        data.loan[cycle] = debt[cycle] - debt[cycle - 1]
        data.bank_equity[cycle] = debt[cycle] - money_stock[cycle]
        data.bank_profit_rate[cycle] = (data.bank_equity[cycle] - data.bank_equity[cycle - 1]) / (data.bank_equity[cycle - 1])
    end

    data.growth[1] = data.growth[2]
    data.loan[1] = data.loan[2]
    data.bank_profit_rate[1] = data.bank_profit_rate[2]

    return data
end

function plot_required_loan_ratio(data::SimData)
    money_stock = .+(data.available, data.saved)
    series = ./(100 * data.required_loan, money_stock)
    plot(series, label = "LR", title = "Loan ratio (" * string(length(data)) * " years)")
    xaxis!("Years")
    yaxis!("Percentage")

    return last(series)
end

function plot_debt_ratio(data::SimData)
    money_stock = .+(data.available, data.saved)
    series = ./(100 * data.debt, money_stock)
    plot(series, label = "DR", title = "Debt ratio (" * string(length(data)) * " years)")
    xaxis!("Years")
    yaxis!("Percentage")

    return last(series)
end

function plot_growth(data::SimData)
    series = .*(data.growth, 100)
    plot(series, label = "g", title = "Growth (" * string(length(data)) * " years)")
    xaxis!("Years")
    yaxis!("Percentage")

    return last(series)
end

function plot_money_stock(data::SimData)
    series = .+(data.available, data.saved)
    plot(series, label = "M", title = "Money stock (" * string(length(data)) * " years)")
    xaxis!("Years")
    yaxis!("Stock")

    return last(series)
end

function plot_data(mode::Mode, m::Real, p::Real, s::Real, maturity::Integer, cycles::Integer = 100)
    data = simulate_banks(mode, m, 1000000, 1, p, s, maturity, cycles)
    m = Fixed(4)(m * 100)
    p = Fixed(4)(p * 100)
    s = Fixed(4)(s * 100)

    if mode == fixed_growth
        LR = plot_required_loan_ratio(data)
        savefig("plots/" * string(mode) * "_LR_growth_" * string(m) * "_profit_" * string(p) * "_save_" * string(s) * "_" * string(maturity) * "_" * string(cycles) * ".png")
        DR = plot_debt_ratio(data)
        savefig("plots/" * string(mode) * "_DR_growth_" * string(m) * "_profit_" * string(p) * "_save_" * string(s) * "_" * string(maturity) * "_" * string(cycles) * ".png")

        return LR, DR
    else
        g = plot_growth(data)
        savefig("plots/" * string(mode) * "_g_LR_" * string(m) * "_profit_" * string(p) * "_save_" * string(s) * "_" * string(maturity) * "_" * string(cycles) * ".png")
        M = plot_money_stock(data)
        savefig("plots/" * string(mode) * "_M_LR_" * string(m) * "_profit_" * string(p) * "_save_" * string(s) * "_" * string(maturity) * "_" * string(cycles) * ".png")
        DR = plot_debt_ratio(data)
        savefig("plots/" * string(mode) * "_DR_LR_" * string(m) * "_profit_" * string(p) * "_save_" * string(s) * "_" * string(maturity) * "_" * string(cycles) * ".png")

        return g, DR, last(data.loan_rate)
    end
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
