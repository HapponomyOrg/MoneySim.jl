using EconoSim
using CSV
using DataFrames
using Random

@enum Transaction buy sell
set_currency_precision!(2)

SEP = "\n"
VAL = " # "

function str_to_dict(string::AbstractString)
    tuple_dict = occursin(VAL, string)

    if tuple_dict
        dict = Dict{Int, Tuple{Int, Currency}}()
    else
        dict = Dict{Int, Int}()
    end

    pairs = occursin(SEP, string) ? split(string, SEP) : [string]

    for pair in pairs
        elements = split(pair, " => ")
        key = parse(Int, elements[1])
        
        if tuple_dict
            t = split(elements[2], VAL)
            dict[key] = (parse(Int, t[1]), parse(Currency, t[2]))
        else
            dict[key] = parse(Int, elements[2])
        end
    end

    return dict
end

function prepare_trade(wallet_value::Number, cash::Number, num_stocks = 427)
    dir = pwd()
    cd("/Users/stef/Programming/Visual Studio/MoneySim.jl/data/beursrally/")

    if isfile("2025.csv")
        data = DataFrame(Day = Int[],
                        Stocks = Int[],
                        Cash = Currency[],
                        Walletvalue = Currency[],
                        Wallet = Dict{Int, Int}[], # stock id => number
                        Bought = Dict{Int, Tuple{Int, Currency}}[], # stock id => number, stock value
                        Sold = Dict{Int, Tuple{Int, Currency}}[]) # stock id => number, stock value
        string_data = CSV.read("2025.csv", DataFrame)

        for row in eachrow(string_data)
            wallet = row[5] isa Missing ? Dict{Int, Int}() : str_to_dict(row[5])
            bought = row[6] isa Missing ? Dict{Int, Tuple{Int, Currency}}() : str_to_dict(row[6])
            sold = row[7] isa Missing ? Dict{Int, Tuple{Int, Currency}}() : str_to_dict(row[7])
            push!(data, [row[1] row[2] Currency(row[3]) Currency(row[4]) wallet bought sold])
        end
    else
        data = DataFrame(Day = [0],
                        Stocks = [num_stocks],
                        Cash = Currency[cash],
                        Walletvalue = Currency[wallet_value],
                        Wallet = Dict{Int, Int}[Dict()], # stock id => number
                        Bought = Dict{Int, Tuple{Int, Currency}}[Dict()], # stock id => number, stock value
                        Sold = Dict{Int, Tuple{Int, Currency}}[Dict()]) # stock id => number, stock value
    end

    cd(dir)

    push!(data, [
                [get_day(data) + 1]
                [num_stocks]
                [Currency(cash)]
                [Currency(wallet_value)]
                [Dict(get_wallet(data))]
                [Dict()] # Only record buys on current day
                [Dict()] # Only record sales on current day
                ])

    return data
end

function get_day(data::DataFrame)
    return data[size(data)[1], 1]
end

function get_stocks(data::DataFrame)
    return data[size(data)[1], 2]
end

function get_cash(data::DataFrame)
    return data[size(data)[1], 3]
end

function spend_cash(data::DataFrame, amount::Number)
    data[size(data)[1], 3] = get_cash(data) - amount
end

function get_wallet_value(data::DataFrame)
    return data[size(data)[1], 4]
end

function get_wallet(data::DataFrame)
    return data[size(data)[1], 5]
end

function get_bought(data::DataFrame)
    return data[size(data)[1], 6]
end

function get_sold(data::DataFrame)
    return data[size(data)[1], 7]
end

function get_stock_position(data::DataFrame, stock_id::Int)
    wallet = get_wallet(data)

    if haskey(wallet, stock_id)
        return wallet[stock_id]
    else
        return 0
    end
end

function suggest_trade(data::DataFrame)
    transaction = get_cash(data) > min(5000, get_wallet_value(data) / 10) ? buy : sell
    stock_id = 0

    if transaction == buy
        stock_id = rand(1:get_stocks(data))
    else
        stock_ids = collect(keys(get_wallet(data)))
        stock_id = stock_ids[rand(1:length(stock_ids))]
    end

    return (stock_id, transaction), stock_block(stock_id)
end

function stock_block(stock_id::Int)
    return Int(trunc((stock_id + 9) / 10)), mod(stock_id, 10) == 0 ? 10 : mod(stock_id, 10)
end

function prep_trade(data::DataFrame, suggestion::Tuple{Int, Transaction}, value::Number)
    stock_id = suggestion[1]
    transaction = suggestion[2]
    value = Currency(value)
    wallet = get_wallet(data)

    if transaction == buy
        buy_treshold = Currency(min(get_wallet_value(data) / 10, get_cash(data)))
        max_stocks = floor(buy_treshold / value) - get_stock_position(data, stock_id)

        if max_stocks > 0
            num_stocks = rand(1:max_stocks)

            return (stock_id, Int(num_stocks), value, buy)
        else
            return "No trade possible - new suggestion: ", suggest_trade(data)
        end
    else
        cur_stocks = wallet[stock_id]
        num_stocks = floor(rand(1:5) * cur_stocks / 5)


        return (stock_id, Int(num_stocks), value, sell)
    end
end

function trade(data::DataFrame, trade::Tuple{Int, Int, Currency, Transaction}, transaction_cost::Number = 0,real_value::Number = t[3])
    wallet = get_wallet(data)
    stock_id = trade[1]
    num_stocks = trade[2]
    value = trade[3]
    transaction = trade[4]

    if transaction == buy
        bought = get_bought(data)

        if haskey(wallet, stock_id)
            wallet[stock_id] = wallet[stock_id] + num_stocks
        else
            wallet[stock_id] = num_stocks
        end

        if haskey(bought, stock_id)
            cur_buy = bought[stock_id]
            new_buy = (cur_buy[1] + num_stocks, value)
            bought[stock_id] = new_buy
        else
            bought[stock_id] = (num_stocks, value)
        end

        spend_cash(data, real_value * num_stocks + transaction_cost)
    else
        wallet[stock_id] = wallet[stock_id] - num_stocks

        if wallet[stock_id] == 0
            delete!(wallet, stock_id)
        end

        sold = get_sold(data)

        if haskey(sold, stock_id)
            cur_sell = sold[stock_id]
            new_sell = (cur_sell[1] + num_stocks, value)
            sold[stock_id] = new_sell
        else
            sold[stock_id] = (num_stocks, value)
        end

        spend_cash(data, -real_value * num_stocks + transaction_cost)
    end

    return data
end

function dict_to_str(dict::Dict)
    str = ""

    for pair in pairs(dict)
        if length(str) > 0
            str *= SEP
        end

        if pair[2] isa Tuple
            str *= string(pair[1]) * " => " * string(pair[2][1]) * VAL * string(pair[2][2])
        else
            str *= string(pair)
        end
    end

    return str
end

function write_data(data::DataFrame)
    cvs_data = DataFrame(Day = Int[],
                        Stocks = Int[],
                        Cash = Currency[],
                        Walletvalue = Currency[],
                        Wallet = String[],
                        Bought = String[],
                        Sold = String[])

    for row in eachrow(data)
        push!(cvs_data, [row[1] row[2] row[3] row[4] dict_to_str(row[5]) dict_to_str(row[6]) dict_to_str(row[7])])
    end

    dir = pwd()
    cd("/Users/stef/Programming/Visual Studio/MoneySim.jl/data/beursrally/")
    CSV.write("2025.csv", cvs_data)

    cd(dir)
end