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
    * bottom_0_1::Union{Nothing, C} : the average wealth of the bottom 1%. Nothing if not applicable.
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
    InequalityData(top_0_1::Union{Nothing, Real},
                    top_1::Union{Nothing, Real},
                    top_10::Real,
                    high_middle_40::Real,
                    low_middle_40::Real,
                    bottom_10::Real,
                    bottom_1::Union{Nothing, Real},
                    bottom_0_1::Union{Nothing, Real}) = new{Currency}(top_0_1,
                                                            top_1,
                                                            top_10,
                                                            high_middle_40,
                                                            low_middle_40,
                                                            bottom_10,
                                                            bottom_1,
                                                            bottom_0_1)
end

function average_wealth(inequality_data::InequalityData)
    return Currency(inequality_data.bottom_10 * 0.1
                    + inequality_data.low_middle_40 * 0.4
                    + inequality_data.high_middle_40 * 0.4
                    + inequality_data.top_10 * 0.1)
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
    adjust_for_overlap(inequality_data::InequalityData, num_actors::Int)

    Adjusts the inequality data for overlap in the percentiles according to the number of actors.
    If there are not enough actors to represent all percentiles, the 
"""
function adjust_for_overlap(inequality_data::InequalityData,
                            num_actors::Int)
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

    return bottom_0_1, bottom_1, bottom_10, top_10, top_1, top_0_1
end

"""
    scale_inequality_data(InequalityData::inequality_data, amount_per_capita::Real)

    Scales every percentile to match the new average amount per capita.
    * inequality_data::InequalityData - The original inequality data.
    * amount_per_capita::Real - The average wealth/income/capital per capita to scale to.
    * Returns: a new, scaled InequalityData structure.
"""
function scale_inequality_data(inequality_data::InequalityData, amount_per_capita::Real)
    avg_amount = round(inequality_data.top_10 * 0.1
                        + inequality_data.high_middle_40 * 0.4
                        + inequality_data.low_middle_40 * 0.4
                        + inequality_data.bottom_10 * 0.1,
                        digits = 4)

    scaled_amount_ratio = amount_per_capita / avg_amount

    return InequalityData(isnothing(inequality_data.top_0_1) ? nothing : inequality_data.top_0_1 * scaled_amount_ratio,
                            isnothing(inequality_data.top_1) ? nothing : inequality_data.top_1 * scaled_amount_ratio,
                            inequality_data.top_10 * scaled_amount_ratio,
                            inequality_data.high_middle_40 * scaled_amount_ratio,
                            inequality_data.low_middle_40 * scaled_amount_ratio,
                            inequality_data.bottom_10 * scaled_amount_ratio,
                            isnothing(inequality_data.bottom_1) ? nothing : inequality_data.bottom_1 * scaled_amount_ratio,
                            isnothing(inequality_data.bottom_0_1) ? nothing : inequality_data.bottom_0_1 * scaled_amount_ratio)
end

"""
    distribute_inequal_wealth!(actors::Vector{<:AbstractActor},
                                inequality_data::InequalityData)
    Distributes the wealth among the actors according to the inequality data.

    When one or more of the optional tiers of inequality data are defined, the wealth of the remaining actors of the tier(s) it belongs to is recalculated.

    Example:
    If there are 1000 actors and the average wealth of the top 0.1% is defined, then the one actor that is the top 0.1% is assigned that wealth.
    For the 9 remaining actors that represent the top 1%, their average wealth is recalculated as follows:
    avg_wealth = (avg_wealth_of_top_1 * 10 - avg_wealth_of_top_0_1) / 9.

    If top_1 is nothing, it is assumed that top_0_1 is also nothing. The same is true for bottom_1 and bottom_0_1.

    * actors::Vector{<:AbstractActor} - The vector of actors the wealth needs to be distributed among.
    * inequality_data::InequalityData - The inequality data to use.
"""
function distribute_inequal_wealth!(actors::Vector{<:AbstractActor},
                                    inequality_data::InequalityData)
    num_actors = length(actors)
    percentiles = calculate_percentile_ranges(num_actors)
    wealth_vector = Vector{Currency}()

    bottom_0_1, bottom_1, bottom_10, top_10, top_1, top_0_1 = adjust_for_overlap(inequality_data, num_actors)

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