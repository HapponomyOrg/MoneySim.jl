using EconoSim
using FixedPointDecimals
using Todo
using Agents

"""
    InequalityData

    * top_0_1::Union{Nothing, C} : the average wealth of the top 0.1%. Nothing if not applicable.
    * top_1::Union{Nothing, C} : the average wealth of the top 1%. Nothing if not applicable.
    * top_10::C : the average wealth of the top 10%.
    * high_middle_40::C : the average wealth of the high middle 40%.
    * low_middle_40::C : the average wealth of the low middle 40%.
    * bottom_10::C : the average wealth of the bottom 10%.
    * bottom_1::Union{Nothing, C} : the average wealth of the bottom 1%. Nothing if not applicable.

    When one or more of the optional tiers are defined, the wealth of the remaining actors of the tier(s) it belongs to is recalculated.

    Example:
    If there are 1000 actors and the average wealth of the top 0.1% is defined, then the one actor that is the top 0.1% is assigned that wealth.
    For the 9 remaining actors that represent the top 1%, their average wealth is recalculated as follows:
    avg_wealth = (avg_wealth_of_top_1 * 10 - avg_wealth_of_top_0_1) / 9.

    If top_1 is nothing, it is assumed that top_0_1 is also nothing. The same is true for bottom_1 and bottom_0_1.
"""
struct InequalityData{C <: FixedDecimal}
    top_0_1::Union{Nothing, C}
    top_1::Union{Nothing, C}
    top_10::C
    high_middle_40::C
    low_middle_40::C
    bottom_10::C
    bottom_1::Union{Nothing, C}
    bottom_0_1::Union{Nothing, C}
end

function adjust_for_overlap(slice_0_1::Union{Nothing, Real},
    slice_1::Union{Nothing, Real},
    slice_10::Real)

    if isnothing(slice_0_1) && isnothing(slice_1)
        slice_0_1 = slice_10
        slice_1 = slice_10
    elseif isnothing(slice_0_1)
        slice_0_1 = slice_1
    elseif isnothing(slice_1)
        slice_1 = (slice_0_1 + 9 * slice_10) / 10
    end

    slice_1 = round((10 * slice_1 - slice_0_1) / 9, digits = 4)
    slice_10 = round((100 * slice_10 - 9 * slice_1 - slice_0_1) / 90, digits = 4)

    return slice_0_1, slice_1, slice_10
end

"""
    InequalityData(top_0_1::Union{Nothing, Real},
                   top_1::Union{Nothing, Real},
                   top_10::Real,
                   high_middle_40::Real,
                   low_middle_40::Real,
                   bottom_10::Real,
                   bottom_1::Union{Nothing, Real},
                   bottom_0_1::Union{Nothing, Real};
                   money_per_head::Union{Nothing, Real} = nothing,
                   allow_negatives::Bool = false)

    * top_0_1::Union{Nothing, Real} : the average wealth of the top 0.1%. Nothing if not applicable.
    * top_1::Union{Nothing, Real} : the average wealth of the top 1%. Nothing if not applicable.
    * top_10::Real : the average wealth of the top 10%.
    * high_middle_40::Real : the average wealth of the high middle 40%.
    * low_middle_40::Real : the average wealth of the low middle 40%.
    * bottom_10::Real : the average wealth of the bottom 10%.
    * bottom_1::Union{Nothing, Real} : the average wealth of the bottom 1%. Nothing if not applicable.
    * bottom_0_1::Union{Nothing, Real} : the average wealth of the bottom 0.1%. Nothing if not applicable.
    * money_per_head::Union{Nothing, Real} : the amount of money per head. Nothing if not applicable.
                                             If defined, the wealth of each tier is proportionally scaled to this value.
    * allow_negatives::Bool : whether or not to allow negative wealth. Default is false.

    Returns an InequalityData object.
"""
function InequalityData(top_0_1::Union{Nothing, Real},
                        top_1::Union{Nothing, Real},
                        top_10::Real,
                        high_middle_40::Real,
                        low_middle_40::Real,
                        bottom_10::Real,
                        bottom_1::Union{Nothing, Real},
                        bottom_0_1::Union{Nothing, Real};
                        money_per_head::Union{Nothing, Real} = nothing)
    money_wealth_ratio = 1

    # Scale to money per head
    if !isnothing(money_per_head)
        avg_money = round(top_10 * 0.1
                            + high_middle_40 * 0.4
                            + low_middle_40 * 0.4
                            + bottom_10 * 0.1,
                            digits = 4)
        money_wealth_ratio = money_per_head / avg_money
    end

    return InequalityData{Currency}(isnothing(top_0_1) ? nothing : top_0_1 * money_wealth_ratio,
                                    isnothing(top_1) ? nothing : top_1 * money_wealth_ratio,
                                    top_10 * money_wealth_ratio,
                                    high_middle_40 * money_wealth_ratio,
                                    low_middle_40 * money_wealth_ratio,
                                    bottom_10 * money_wealth_ratio,
                                    isnothing(bottom_1) ? nothing : bottom_1 * money_wealth_ratio,
                                    isnothing(bottom_0_1) ? nothing : bottom_0_1 * money_wealth_ratio)
end

function distribute_inequal_wealth!(actors::Vector{<:AbstractActor},
                                    inequality_data::InequalityData)
    num_actors = length(actors)
    percentiles = calculate_percentile_ranges(num_actors)
    wealth_vector = Vector{Currency}()

    bottom_0_1 = inequality_data.bottom_0_1
    bottom_1 = inequality_data.bottom_1
    bottom_10 = inequality_data.bottom_10
    top_10 = inequality_data.top_10
    top_1 = inequality_data.top_1
    top_0_1 = inequality_data.top_0_1

    if num_actors >= 1000
        top_0_1, top_1, top_10 = adjust_for_overlap(top_0_1, top_1, top_10)
        bottom_0_1, bottom_1, bottom_10 = adjust_for_overlap(bottom_0_1, bottom_1, bottom_10)
    elseif num_actors >= 100
        top_0_1, top_1, top_10 = adjust_for_overlap(nothing, top_1, top_10)
        bottom_0_1, bottom_1, bottom_10 = adjust_for_overlap(nothing, bottom_1, bottom_10)
    else
        top_0_1, top_1, top_10 = adjust_for_overlap(nothing, nothing, top_10)
        bottom_0_1, bottom_1, bottom_10 = adjust_for_overlap(nothing, nothing, bottom_10)
    end

    if num_actors >= 100
        if num_actors >= 1000
            for _ in percentiles[1]
                push!(wealth_vector, bottom_0_1)
            end

            for _ in (percentiles[1].stop + 1):percentiles[2].stop
                push!(wealth_vector, bottom_1)
            end
        else
            for _ in percentiles[2]
                push!(wealth_vector, bottom_1)
            end
        end

        for _ in (percentiles[2].stop + 1):percentiles[3].stop
            push!(wealth_vector, bottom_10)
        end
    else
        for _ in percentiles[3]
            push!(wealth_vector, bottom_10)
        end
    end

    for _ in percentiles[5]
        push!(wealth_vector, inequality_data.low_middle_40)
    end

    for _ in percentiles[6]
        push!(wealth_vector, inequality_data.high_middle_40)
    end

    if num_actors >= 100
        if num_actors >= 1000
            for _ in percentiles[9]
                push!(wealth_vector, top_0_1)
            end

            for _ in percentiles[8].start:(percentiles[9].start - 1)
                push!(wealth_vector, top_1)
            end
        else
            for _ in percentiles[8]
                push!(wealth_vector, top_1)
            end
        end

        for _ in percentiles[7].start:(percentiles[8].start - 1)
            push!(wealth_vector, top_10)
        end
    else
        for _ in percentiles[7]
            push!(wealth_vector, top_10)
        end
    end

    for actor in actors
        book_asset!(get_balance(actor), SUMSY_DEP, wealth_vector[num_actors], set_to_value = true)

        num_actors -= 1
    end
end