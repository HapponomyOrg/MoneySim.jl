using EconoSim
using Random
using Agents
using FixedPointDecimals
using DataFrames
using Todo

abstract type MonetaryModelParams{C <: FixedDecimal} end

# Fixed wealth

struct FixedWealthParams{C <: FixedDecimal} <: MonetaryModelParams{C}
    initial_wealth::C
    wealth_distributed::Bool
    FixedWealthParams(initial_wealth::Real,
                        wealth_distributed::Bool) = new{Currency}(initial_wealth, wealth_distributed)
end

"""
    Must be called after initialize_population_model!
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
Must be called after initialize_population_model!
"""
struct StandardSuMSyParams{C <: FixedDecimal, FC <: Function, FD <: Function} <: SuMSyParams{C}
    sumsy_interval::Int
    transactional::Bool
    configure_sumsy_actors!::FC
    distribute_wealth!::FD
    StandardSuMSyParams(;sumsy_interval::Int,
                            transactional::Bool,
                            configure_sumsy_actors!::Function,
                            distribute_wealth!::Function) = new{Currency,
                                                                typeof(configure_sumsy_actors!),
                                                                typeof(distribute_wealth!)}(sumsy_interval,
                                                                                            transactional,
                                                                                            configure_sumsy_actors!,
                                                                                            distribute_wealth!)
end

function create_StandardSuMSyParams(;sumsy_interval::Int,
                                    transactional::Bool,
                                    configure_sumsy_actors!::Function = mixed_actors!,
                                    initial_gi_wealth::Real = 0,
                                    initial_non_gi_wealth::Real = 0,
                                    distribute::Bool = true)
    if distribute
        distribute_wealth! = x -> equal_wealth_distribution!(x, initial_gi_wealth, initial_non_gi_wealth)
    else
        distribute_wealth! = x -> concentrated_wealth_distribution!(x, initial_gi_wealth, initial_non_gi_wealth)
    end

    return StandardSuMSyParams{Currency, typeof(configure_sumsy_actors!), typeof(distribute_wealth!)}(sumsy_interval,
                                        transactional,
                                        configure_sumsy_actors!,
                                        distribute_wealth!)
end

function equal_wealth_distribution!(model::ABM, initial_gi_wealth::Real, initial_non_gi_wealth::Real)
    for actor in allagents(model)
        if is_gi_eligible(actor)
            book_asset!(get_balance(actor), SUMSY_DEP, initial_gi_wealth)
        else
            book_asset!(get_balance(actor), SUMSY_DEP, initial_non_gi_wealth)
        end
    end
end

function concentrated_wealth_distribution!(model::ABM, initial_gi_wealth::Real, initial_non_gi_wealth::Real)
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
                initial_gi_wealth * num_gi_eligible
                    + initial_non_gi_wealth * num_non_gi_eligible)
end

"""
    percentage_gi_actors!

        Must be called after initialize_population_model!

    * model::ABM
    * gi_actor_percentage::Percentage

    Use this function to set a percentage of actors as gi eligible actors.
    If the percentage is less than 1.0, define a new function based on this one to set the configure_sumsy_actors! as follows:
        configure_sumsy_actors! = model -> percentage_gi_actors!(model, gi_actor_percentage)
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

        Must be called after initialize_population_model!
    
    * model::ABM
    * num_gi_actors::{Int, Nothing} : The number of actors that are gi eligible. All other actors are set to non-gi eligible. If nothing is passed, all actors are gi eligible.

    Use this function to set the number of gi eligible actors.
    If not all actors are gi eligible, define a new function based on this one to set the configure_sumsy_actors! as follows:
        configure_sumsy_actors! = model -> mixed_actors!(model, num_gi_actors)
"""
function mixed_actors!(model::ABM, num_gi_actors::Union{Int, Nothing} = nothing)
    num_gi = 0

    for actor in allagents(model)
        if isnothing(num_gi_actors) || num_gi < num_gi_actors
            set_gi_eligible!(actor, true)
        else
            set_gi_eligible!(actor, false)
        end

        num_gi += 1
    end
end

"""
    typed_gi_actors!

        Must be called after initialize_population_model!

    * model::ABM
    * sumsy_params::SuMSyParams
    * gi_actor_types::Set{Symbol} : types of actors that are gi eligible.

    Use this function to set a percentage of actors as gi eligible actors.
    If the percentage is less than 1.0, define a new function based on this one to set the configure_sumsy_actors! as follows:
        configure_sumsy_actors! = model -> typed_gi_actors!(model, gi_actor_types)
"""
function typed_gi_actors!(model::ABM, gi_actor_types::Vector{Symbol})
    gi_actor_types = unique(gi_actor_types)

    for actor in allagents(model)
        gi_eligible = !isempty(intersect(actor.types, gi_actor_types))
        set_gi_eligible!(actor, gi_eligible)
    end
end

"""
    type_based_sumsy_actors!

        Must be called after initialize_population_model!

    * model::ABM
    * sumsy_groups::Dict{Symbol, Tuple{Real, Real}} : actor types and their guaranteed income and demurrage free buffer.
    * demurrage::DemSettings - The demurrage for all actors.

    Sets the guaranteed income for actors based on their actor type.
"""
function type_based_sumsy_actors!(model::ABM, sumsy_groups::Dict{Symbol, Tuple{Real, Real}}, demurrage::DemSettings)
    sumsy_dict = Dict{Symbol, SuMSy}()

    for type in keys(sumsy_groups)
        sumsy_dict[type] = SuMSy(sumsy_groups[type][1],
                                sumsy_groups[type][2],
                                demurrage)
    end

    for actor in allagents(model)
        actor_types = actor.types

        for actor_type in actor_types
            if haskey(sumsy_dict, actor_type)
                set_sumsy!(get_balance(actor), sumsy_dict[actor_type])
            end
        end
    end
end

function initialize_monetary_model!(model::ABM,
                                    sumsy_params::StandardSuMSyParams)
    sumsy_params.configure_sumsy_actors!(model)
    sumsy_params.distribute_wealth!(model)
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
end

function InequalityData(top_0_1::Union{Nothing, Real},
                        top_1::Union{Nothing, Real},
                        top_10::Real,
                        high_middle_40::Real,
                        low_middle_40::Real,
                        bottom_10::Real,
                        bottom_1::Union{Nothing, Real},
                        bottom_0_1::Union{Nothing, Real};
                        money_per_head::Union{Nothing, Real} = nothing,
                        allow_negatives::Bool = false)
    money_wealth_ratio = 1

    @todo_str "Correct upward shift so that ratios are maintained."
    # Adjust up if negatives are not allowed
    if !allow_negatives
        bottom = 0

        if !isnothing(bottom_0_1)
            bottom = min(bottom, bottom_0_1)
        elseif !isnothing(bottom_1)
            bottom = min(bottom, bottom_1)
        else
            bottom = min(bottom, bottom_10)
        end

        if bottom < 0
            if !isnothing(top_0_1)
                top_0_1 -= bottom
            end

            if !isnothing(top_1)
                top_1 -= bottom
            end

            top_10 -= bottom
            high_middle_40 -= bottom
            low_middle_40 -= bottom
            bottom_10 -= bottom

            if !isnothing(bottom_1)
                bottom_1 -= bottom
            end

            if !isnothing(bottom_0_1)
                bottom_0_1 -= bottom
            end
        end
    end

    # Scale to money per head
    if !isnothing(money_per_head)
        avg_wealth = 0.1 * top_10 + 0.4 * high_middle_40 + 0.4 * low_middle_40 + 0.1 * bottom_10
        money_wealth_ratio = money_per_head / avg_wealth

        if !isnothing(top_0_1)
            top_0_1 *= money_wealth_ratio
        end
    
        if !isnothing(top_1)
            top_1 *= money_wealth_ratio
        end
    
        top_10 *= money_wealth_ratio
        high_middle_40 *= money_wealth_ratio
        low_middle_40 *= money_wealth_ratio
        bottom_10 *= money_wealth_ratio
    
        if !isnothing(bottom_1)
            bottom_1 *= money_wealth_ratio
        end
    
        if !isnothing(bottom_0_1)
            bottom_0_1 *= money_wealth_ratio
        end
    end

    return InequalityData{Currency}(top_0_1,
                                    top_1,
                                    top_10,
                                    high_middle_40,
                                    low_middle_40,
                                    bottom_10,
                                    bottom_1,
                                    bottom_0_1)
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

    if bottom_1 !== nothing && num_actors >= 100
        if bottom_0_1 !== nothing && num_actors >= 1000
            for _ in percentiles[1]
                push!(wealth_vector, bottom_0_1)
            end

            bottom_1 = (bottom_1 * 10 - bottom_0_1) / 9

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
        if top_0_1 !== nothing && num_actors >= 1000
            for _ in percentiles[9]
                push!(wealth_vector, top_0_1)
            end

            top_1 = (top_1 * 10 - top_0_1) / 9

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

    for actor in actors
        book_asset!(get_balance(actor), SUMSY_DEP, wealth_vector[num_actors], set_to_value = true)
        num_actors -= 1
    end
end

function typed_inequal_wealth_distribution!(model::ABM,
                                            inequality_data::InequalityData,
                                            actor_types::Vector{Symbol})
    typed_actors = Dict{Symbol, Vector{<:AbstractActor}}()

    for actor in allagents(model)
        for type in actor_types
            if type in actor.types
                if !haskey(typed_actors, type)
                    typed_actors[type] = [actor]
                else
                    push!(typed_actors[type], actor)
                end
            end
        end
    end

    for actors in values(typed_actors)
        distribute_inequal_wealth!(actors, inequality_data)
    end
end

function inequal_wealth_distribution!(model::ABM,
                                        inequality_data::InequalityData)
    distribute_inequal_wealth!(allagents(model), inequality_data)
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