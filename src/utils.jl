using EconoSim
using Agents

BROKE_THRESHOLD = :broke_threshold

"""
    function is_broke(actor)
        The function first checks whether the model has the BROKE_TRESHOLD field.
        If so, the function returns true if the actor's balance is beneath the BROKE_TRESHOLD.
        Otherwise, the function returns false.
"""
function is_broke(actor)
    try
        return asset_value(get_balance(actor), SUMSY_DEP) < actor.model.broke_threshold
    catch
        return false
    end
end

function one_non_broke(model::ABM)
    non_broke = 0

    for actor in allagents(model)
        if !is_broke(actor)
            non_broke += 1

            if non_broke > 1
                return false
            end
        end
    end

    return true
end

function remove_index(vector::Vector{Int}, index::Int)
    res = Vector{Int}(vector)

    return deleteat!(res, index)
end

@enum Percentiles BOTTOM_0_1 BOTTOM_1 BOTTOM_10 BOTTOM_50 LOW_MIDDLE_40 HIGH_MIDDLE_40 TOP_10 TOP_1 TOP_0_1

function calculate_percentile_ranges(num_actors::Int)
    bottom_0_1 = 1:Int64(round(num_actors / 1000))
    bottom_1 = 1:Int64(round(num_actors / 100))
    bottom_10 = 1:Int64(round(num_actors / 10))
    bottom_50 = 1:Int64(round(num_actors / 2))
    low_middle_40 = (bottom_10[end] + 1):Int64(round(num_actors / 2))
    high_middle_40 = (low_middle_40[end] + 1):Int64(round(num_actors - num_actors / 10))
    top_10 = (high_middle_40[end] + 1):num_actors
    top_1 = Int64(round(num_actors - num_actors / 100 + 1)):num_actors
    top_0_1 = Int64(round(num_actors + 1 - num_actors / 1000)):num_actors
    return [bottom_0_1, bottom_1, bottom_10, bottom_50, low_middle_40, high_middle_40, top_10, top_1, top_0_1]
end

function calculate_taxes(;years::Int = 1,
                        tax_type::TAX_TYPE = DEMURRAGE_TAX,
                        tax_brackets = DEM_TAX,
                        guaranteed_income::Real = 2000,
                        dem_free::Real = 0,
                        demurrage::DemSettings = DEMOGRAPHIC_DEM,
                        start_balance::Real = 0,
                        income::Real = 0,
                        expenses::Real = 0,
                        transactional::Bool = false)
    timestamp = 0
    sumsy = SuMSy(guaranteed_income, dem_free, demurrage)
    tax_brackets = make_tiers(tax_brackets)
    balance = SingleSuMSyBalance(sumsy, sumsy_interval = 30, transactional = transactional, allow_negative_sumsy = true)
    book_sumsy!(balance, start_balance, timestamp = timestamp)

    taxes = DataFrame(year = Int64[], tax = Currency[], year_dem = Currency[], balance = Currency[])

    for year in 1:years
        tax = 0
        year_dem = 0

        for _ in 1:12
            book_sumsy!(balance, income - expenses, timestamp = timestamp)
            timestamp += 30

            _, dem = calculate_timerange_adjustments(balance, timestamp - get_last_adjustment(balance))
            year_dem += dem

            if tax_type == DEMURRAGE_TAX
                dem_tax = calculate_time_range_demurrage(asset_value(balance, SUMSY_DEP),
                                                        tax_brackets,
                                                        dem_free,
                                                        30,
                                                        timestamp - get_last_adjustment(balance),
                                                        false)
                tax += dem_tax
                book_sumsy!(balance, -dem_tax, timestamp = timestamp)
            end

            book_sumsy!(balance, guaranteed_income - dem, timestamp = timestamp)
            set_last_adjustment!(balance, timestamp)
        end
        
        if tax_type == INCOME_TAX
            tax = calculate_time_range_demurrage(12 * income,
                                                tax_brackets,
                                                dem_free,
                                                30,
                                                30,
                                                false)
            book_sumsy!(balance, -tax, timestamp = timestamp)
        end

        push!(taxes, (year, tax, year_dem, asset_value(balance, SUMSY_DEP)))
    end

    return taxes
end