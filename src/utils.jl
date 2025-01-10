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