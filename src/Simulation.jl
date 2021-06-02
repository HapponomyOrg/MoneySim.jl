using EconoSim # EconoSim 0.1.2 or https://github.com/HapponomyOrg/EconoSim.jl
using Plots
using CSV

struct SimData
    growth::Vector{Fixed(4)}
    bank_profit_rate::Vector{Fixed(4)}
    qe_adjustment::Vector{Currency}
    available::Vector{Currency}
    parked::Vector{Currency}
    debt::Vector{Currency}
    installment::Vector{Currency}
    required_lending::Vector{Currency}
    lending::Vector{Currency}
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

# agregate bank balance sheet
bank = Balance(def_min_asset = typemin(Currency), log_transactions = false)
# aggregate balance for money available to pay off debt
available = Balance(def_min_asset = typemin(Currency), log_transactions = false)
# aggregate balance to 'park' money not available to pay off debt
parked = Balance(def_min_asset = typemin(Currency), log_transactions = false)

current_available() = asset_value(available, DEPOSIT)
current_parked() = asset_value(parked, DEPOSIT)
current_money_stock() = current_available() + current_parked()

function process_cycle!(cycle::Integer,
                    data::SimData,
                    target_money_stock::Real,
                    loans::Vector{Debt},
                    bank_profit_rate::Real,
                    park_ratio::Real,
                    maturity::Integer,
                    lending_satisfaction::Real)
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

    # determine required and real lending
    data.required_lending[cycle] = max(0, target_money_stock - current_money_stock())
    data.lending[cycle] = data.required_lending[cycle] * lending_satisfaction

    if data.lending[cycle] > 0
        push!(loans, bank_loan(bank, available, data.lending[cycle], bank_profit_rate, maturity))
    end

    # park money if available
    transfer_asset!(available, parked, DEPOSIT, max(0, current_available() * park_ratio))

    data.growth[cycle] = (current_money_stock() - money_stock) / money_stock
    data.bank_profit_rate[cycle] = bank_profit_rate
    data.available[cycle] = current_available()
    data.parked[cycle] = current_parked()
    data.debt[cycle] = asset_value(bank, DEBT)
    data.bank_equity[cycle] = liability_value(bank, EQUITY)
end

"""
    simulate_banks(money_stock::Real,
                debt::Real,
                growth::Real,
                interest::Real,
                maturity::Integer,
                cycles::Integer)

# Arguments
* money_stock::Real - The initial money stock.
* debt_ratio::Real - The initial debt ratio.
* growth_ratio::Real - The growth factor of the money stock per cycle.
* bank_profit_rate::Real - The net bank profit rate on bank debt per cycle.
* park_ratio::Real - The percentage of money stock which is parked each cycle. This money is not available to pay off debt with. Parked money is part of the money stock.
* maturity::Integer - The maturity of the loans.
* cycles::Integer - The number of cycles the simulation runs.
* lending_satisfaction::Real - The satisfaction rate of the required lending.
"""
function simulate_banks(money_stock::Real,
                debt_ratio::Real,
                growth_ratio::Real,
                bank_profit_rate::Real,
                park_ratio::Real,
                maturity::Integer,
                cycles::Integer;
                lending_satisfaction::Real = 1)
    money_stock = Currency(money_stock)
    debt = money_stock * debt_ratio # determine debt

    # reset balance sheets
    clear!(bank)
    clear!(available)
    clear!(parked)

    loans = Vector{Debt}()
    push!(loans, bank_loan(bank, available, debt, bank_profit_rate, maturity)) # create initial debt

    # Adjust for debt ratio's different from 100%
    book_asset!(available, DEPOSIT, money_stock - debt)
    book_liability!(bank, DEPOSIT, money_stock - debt)

    data = SimData(cycles)

    # run simulation
    for cycle in 1:cycles
        process_cycle!(cycle,
                        data,
                        (1 + growth_ratio) * current_money_stock(),
                        loans,
                        bank_profit_rate,
                        park_ratio,
                        maturity,
                        lending_satisfaction)
    end

    return data
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
    data.parked[1] = savings[1]
    data.available[1] = money_stock[1] - savings[1]
    data.debt[1] = debt[1]
    data.qe_adjustment[1] = qe[1]
    data.bank_equity[1] = debt[1] - money_stock[1]

    for cycle in 2:length(money_stock)
        data.growth[cycle] = (money_stock[cycle] - money_stock[cycle - 1]) / money_stock[cycle - 1]
        data.parked[cycle] = savings[cycle]
        data.available[cycle] = money_stock[cycle] - savings[cycle]
        data.debt[cycle] = debt[cycle]
        data.qe_adjustment[cycle] = data.qe_adjustment[cycle - 1] + qe[cycle]
        data.lending[cycle] = debt[cycle] - debt[cycle - 1]
        data.bank_equity[cycle] = debt[cycle] - money_stock[cycle]
        data.bank_profit_rate[cycle] = (data.bank_equity[cycle] - data.bank_equity[cycle - 1]) / (data.bank_equity[cycle - 1])
    end

    data.growth[1] = data.growth[2]
    data.lending[1] = data.lending[2]
    data.bank_profit_rate[1] = data.bank_profit_rate[2]

    return data
end

function plot_data(data::SimData)
    money_stock = .+(data.available, data.parked)
    qe_adjusted_money_stock = .-(money_stock, data.qe_adjustment)

    plot(data.growth, label = "Growth")

    plot(data.debt, label = "Debt")

    plot(money_stock, label = "Money stock")
    plot!(data.available, label = "Available")
    plot!(data.parked, label = "Parked")

    plot(./(data.debt, money_stock), label = "Debt ratio")
    plot!(./(data.debt, data.available), label = "Available debt ratio")

    plot(./(data.required_lending, money_stock), label = "Required lending ratio")
    plot!(./(data.required_lending, data.available), label = "Required available lending ratio")
    plot!(./(data.lending, money_stock), label = "Lending ratio")
    plot!(./(data.lending, data.available), label = "Available lending ratio")

    plot(./(data.bank_equity + data.parked, money_stock), label = "Parked ratio")

    plot(./(data.lending_rate, data.debt_ratio), label = "Debt ratio / lending rate")

    plot(data.bank_profit_rate, label = "Profit ratio", x = l)
    plot!(data.growth, label = "Growth")

end

# data = simulate_banks(1000000, 1, 0.03, 0.04, 0.05, 20, 500)

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

d = process_csv("Debt - M2.csv")
# sim_data = process_data(d[2], d[1], Vector{Real}(undef, length(d[1])), Vector{Real}(undef, length(d[1])))
