using EconoSim
using Random
using Agents
using FixedPointDecimals
using DataFrames

abstract type MonetaryModelParams{C <: FixedDecimal} end

# Fixed wealth

struct FixedWealthParams{C <: FixedDecimal} <: MonetaryModelParams{C}
    initial_wealth::C
    wealth_distributed::Bool
    FixedWealthParams(initial_wealth::Real,
                        wealth_distributed::Bool) = new{Currency}(initial_wealth, wealth_distributed)
end

"""
    Must be called after initialize_transaction_model!
"""
function initialize_monetary_model!(model::ABM,
                                    fixed_wealth_params::FixedWealthParams)
    if fixed_wealth_params.wealth_distributed
        initial_wealth = fixed_wealth_params.initial_wealth
    else
        total_wealth = nagents(model) * fixed_wealth_params.initial_wealth
        initial_wealth = CUR_0
    end

    for actor in allagents(model)
        actor.model = model
        book_asset!(get_balance(actor), SUMSY_DEP, initial_wealth)
    end
    
    if !fixed_wealth_params.wealth_distributed
        actor = random_agent(model)
        book_asset!(get_balance(actor), SUMSY_DEP, total_wealth)
    end

    return model
end

# SuMSy

abstract type SuMSyParams{C <: FixedDecimal} <: MonetaryModelParams{C} end

"""
SuMSyParams constructor

SuMSyParams can only be used in conjunction with a SuMSy model.
Must be called after initialize_transaction_model!
"""
struct StandardSuMSyParams{C <: FixedDecimal} <: SuMSyParams{C}
    initial_gi_wealth::C
    initial_non_gi_wealth::C
    make_sumsy_actors!::Function
    distribute_wealth!::Function
    StandardSuMSyParams(initial_gi_wealth::Real,
                        initial_non_gi_wealth::Real = 0;
                        make_sumsy_actors!::Function = mixed_actors!,
                        distribute_wealth!::Function = equal_wealth_distribution!) =
                            new{Currency}(initial_gi_wealth,
                                            initial_non_gi_wealth,
                                            make_sumsy_actors!,
                                            distribute_wealth!)
end

function equal_wealth_distribution!(model::ABM, sumsy_params::StandardSuMSyParams)
    for actor in allagents(model)
        if is_gi_eligible(actor)
            book_asset!(get_balance(actor), SUMSY_DEP, sumsy_params.initial_gi_wealth)
        else
            book_asset!(get_balance(actor), SUMSY_DEP, sumsy_params.initial_non_gi_wealth)
        end
    end
end

function concentrated_wealth_distribution!(model::ABM, sumsy_params::StandardSuMSyParams)
    num_gi_eligible = 0
    num_non_gi_eligible = 0

    for actor in allagents(model)
        if is_gi_eligible(actor)
            num_gi_eligible += 1
        else
            num_non_gi_eligible += 1
        end
    end

    book_asset!(get_balance(random_agent(model)),
                SUMSY_DEP,
                sumsy_params.initial_gi_wealth * num_gi_eligible
                    + sumsy_params.initial_non_gi_wealth * num_non_gi_eligible)
end

"""
    percentage_gi_actors!

        Must be called after initialize_transaction_model!

    * model::ABM
    * gi_actor_percentage::Percentage

    Use this function to set a percentage of actors as gi eligible actors.
    If the percentage is less than 1.0, define a new function based on this one to set the make_sumsy_actors! as follows:
        make_sumsy_actors! = model -> percentage_gi_actors!(model, gi_actor_percentage)
"""
function percentage_gi_actors!(model::ABM, gi_actor_percentage::Real = 1.0)
    sumsy = model.sumsy
    gi_actor_percentage = Percentage(gi_actor_percentage)
    num_actors = nagents(model)
    num_gi_actors = round(Int, num_actors * gi_actor_percentage)
    gi_counter = 0

    for actor in allagents(model)
        make_single_sumsy!(model, sumsy, actor, gi_eligible = gi_counter < num_gi_actors, initialize = false)
        gi_counter += 1
    end
end

"""
    mixed_actors

        Must be called after initialize_transaction_model!
    
    * model::ABM
    * num_gi_actors::{Int, Nothing} : The number of actors that are gi eligible. All other actors are set to non-gi eligible. If nothing is passed, all actors are gi eligible.

    Use this function to set the number of gi eligible actors.
    If not all actors are gi eligible, define a new function based on this one to set the make_sumsy_actors! as follows:
        make_sumsy_actors! = model -> mixed_actors!(model, num_gi_actors)
"""
function mixed_actors!(model::ABM, num_gi_actors::Union{Int, Nothing} = nothing)
    sumsy = model.sumsy
    num_gi = 0

    for actor in allagents(model)
        if isnothing(num_gi_actors) || num_gi < num_gi_actors
            make_single_sumsy!(model, sumsy, actor, gi_eligible = true, initialize = false)
        else
            make_single_sumsy!(model, sumsy, actor, gi_eligible = false, initialize = false)
        end

        num_gi += 1
    end
end

"""
    typed_gi_actors!

        Must be called after initialize_transaction_model!

    * model::ABM
    * sumsy_params::SuMSyParams
    * gi_actor_types::Set{Symbol} : types of actors that are gi eligible.

    Use this function to set a percentage of actors as gi eligible actors.
    If the percentage is less than 1.0, define a new function based on this one to set the make_sumsy_actors! as follows:
        make_sumsy_actors! = model -> typed_gi_actors!(model, gi_actor_types)
"""
function typed_gi_actors!(model::ABM, gi_actor_types::Vector{Symbol})
    sumsy = model.sumsy
    gi_actor_types = unique(gi_actor_types)

    for actor in allagents(model)
        gi_eligible = !isempty(intersect(actor.types, gi_actor_types))
        make_single_sumsy!(model, sumsy, actor, gi_eligible = gi_eligible, initialize = false)
    end
end

function initialize_monetary_model!(model::ABM,
                                    sumsy_params::StandardSuMSyParams)
    sumsy_params.make_sumsy_actors!(model)
    sumsy_params.distribute_wealth!(model, sumsy_params)
end

# Inequality SuMSy

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

"""
    InequalitySuMSyParams

    * inequality_data::InequalityData : data on the inequality
    * make_sumsy_actors!::Function : function to make actors
    * distribute_wealth!::Function : function to distribute wealth
"""
struct InequalitySuMSyParams{C <: FixedDecimal} <: SuMSyParams{C}
    inequality_data::InequalityData
    make_sumsy_actors!::Function
    distribute_wealth!::Function
    InequalitySuMSyParams(inequality_data::InequalityData,
                            make_sumsy_actors!::Function = mixed_actors!,
                            distribute_wealth!::Function = inequal_wealth_distribution!) =
                                new{Currency}(inequality_data,
                                                make_sumsy_actors!,
                                                distribute_wealth!)
end

function inequal_wealth_distribution!(model::ABM,
                                        inequality_data::InequalityData)
    num_actors = nagents(model)
    percentiles = calculate_percentile_numbers(num_actors)
    wealth_vector = Vector{Currency}()

    bottom_1 = inequality_data.bottom_1
    bottom_10 = inequality_data.bottom_10
    top_10 = inequality_data.top_10
    top_1 = inequality_data.top_1

    if bottom_1 !== nothing && num_actors >= 100
        if inequality_data.bottom_0_1 !== nothing && num_actors >= 1000
            for _ in percentiles[1]
                push!(wealth_vector, inequality_data.bottom_0_1)
            end

            bottom_1 = (bottom_1 * 10 - inequality_data.bottom_0_1) / 9

            for _ in (percentiles[1].stop + 1):percentiles[2].stop
                push!(wealth_vector, bottom_1)
            end
        else
            for _ in percentiles[2]
                push!(wealth_vector, bottom_1)
            end
        end

        bottom_10 = (bottom_10 * 10 - bottom_1) / 9

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

    if top_1 !== nothing && num_actors >= 100
        if inequality_data.top_0_1 !== nothing && num_actors >= 1000
            for _ in percentiles[9]
                push!(wealth_vector, inequality_data.top_0_1)
            end

            top_1 = (top_1 * 10 - inequality_data.top_0_1) / 9

            for _ in percentiles[8].start:(percentiles[9].start - 1)
                push!(wealth_vector, top_1)
            end
        else
            for _ in percentiles[8]
                push!(wealth_vector, top_1)
            end
        end

        top_10 = (top_10 * 10 - top_1) / 9

        for _ in percentiles[7].start:(percentiles[8].start - 1)
            push!(wealth_vector, top_10)
        end
    else
        for _ in percentiles[7]
            push!(wealth_vector, top_10)
        end
    end

    for actor in allagents(model)
        min_asset!(get_balance(actor), SUMSY_DEP, typemin(Currency))
        book_asset!(get_balance(actor), SUMSY_DEP, wealth_vector[num_actors], set_to_value = true)
        num_actors -= 1
    end
end

function initialize_monetary_model!(model::ABM,
                                    inequality_sumsy_params::InequalitySuMSyParams)
    inequality_sumsy_params.make_sumsy_actors!(model)
    inequality_sumsy_params.distribute_wealth!(model, inequality_sumsy_params.inequality_data)
end

# Debt based with borrowing

struct DebtBasedParams{C <: FixedDecimal} <: MonetaryModelParams{C}
    initial_wealth::C    
    DebtBasedParams(num_actors::Int,
                    initial_wealth::Real) = new{Currency}(num_actors,
                                                            initial_wealth)
end

function initialize_monetary_model!(model::ABM,
                                    debt_based_params::DebtBasedParams)
    abmproperties(model)[:bank] = Balance()

    for actor in allagents(model)
        min_asset!(get_balance(actor), SUMSY_DEP, typemin(Currency))
        book_asset!(get_balance(actor), SUMSY_DEP, debt_based_params.initial_wealth, set_to_value = true)
    end
end