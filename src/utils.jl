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