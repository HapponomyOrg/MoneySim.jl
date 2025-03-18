using EconoSim
using Random
using Agents
using FixedPointDecimals
using DataFrames
using Todo

abstract type MonetaryModelParams end

# Fixed wealth

"""
    FixedWealthParams
    * distribute_wealth::Function : a function that distributes the wealth to all actors.

    The distribute_wealth function must take the model as an argument and distribute the wealth to all actors.
"""
struct FixedWealthParams{F <: Callable} <: MonetaryModelParams
    distribute_wealth::F
    FixedWealthParams(distribute_wealth::Function) = new{typeof(distribute_wealth)}(
                                                            distribute_wealth)
end

"""
    Must be called after initialize_population_model!
"""
function initialize_monetary_model!(model::ABM,
                                    fixed_wealth_params::FixedWealthParams)
    fixed_wealth_params.distribute_wealth(model)

    return model
end

# distribute_wealth functions

"""
    distribute_equal!(model::ABM, initial_wealth::Real)
    * model::ABM : the model to distribute wealth in.
    * initial_wealth::Real : the initial wealth per actor.

    Distributes wealth equally to all actors in the model.
"""
function distribute_equal!(model::ABM, initial_wealth::Real)
    for actor in allagents(model)
        book_asset!(get_balance(actor), SUMSY_DEP, initial_wealth)
    end
end

"""
    concentrate_wealth!(model::ABM, initial_wealth::Real)
    * model::ABM : the model to distribute wealth in.
    * initial_wealth::Real : the initial wealth per actor. One actor will end up with n * initial_wealth, where n is the number of actors in the model.

    Concentrates all wealth in a single actor.
"""
function concentrate_wealth!(model::ABM, initial_wealth::Real)
    book_asset!(get_balance(random_agent(model)), SUMSY_DEP, initial_wealth * nagents(model))
end

"""
    distribute_inequal!(model::ABM, inequality_data::InequalityData)
    * model::ABM : the model to distribute wealth in.
    * inequality_data::InequalityData : the data to use for the distribution.
"""
function distribute_inequal!(model::ABM,
                                inequality_data::InequalityData)
    distribute_inequal_wealth!(collect(allagents(model)), inequality_data)
end

"""
    distribute_inequal!(model::ABM, inequality_data::InequalityData, actor_types::Vector{Symbol})
    * model::ABM : the model to distribute wealth in.
    * inequality_data::InequalityData : the data to use for the distribution.
    * actor_types::Vector{Symbol} : the types of actors to distribute wealth to.
                                    Wealth will be distributed among each type according to the inequality data.
"""
function distribute_inequal!(model::ABM,
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

# SuMSy

abstract type SuMSyParams <: MonetaryModelParams end

"""
SuMSyParams constructor

SuMSyParams can only be used in conjunction with a SuMSy model.
Must be called after initialize_population_model!
"""
struct StandardSuMSyParams{FC <: Callable, FD <: Callable} <: SuMSyParams
    sumsy_interval::Int
    transactional::Bool
    configure_sumsy_actors!::FC
    distribute_wealth!::FD
    StandardSuMSyParams(;sumsy_interval::Int,
                            transactional::Bool,
                            configure_sumsy_actors!::Function,
                            distribute_wealth!::Function) = new{typeof(configure_sumsy_actors!),
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
        distribute_wealth! = x -> distribute_equal!(x, initial_gi_wealth, initial_non_gi_wealth)
    else
        distribute_wealth! = x -> concentrate_wealth!(x, initial_gi_wealth, initial_non_gi_wealth)
    end

    return StandardSuMSyParams(sumsy_interval = sumsy_interval,
                                transactional = transactional,
                                configure_sumsy_actors! = configure_sumsy_actors!,
                                distribute_wealth! = distribute_wealth!)
end

function initialize_monetary_model!(model::ABM,
                                    sumsy_params::StandardSuMSyParams)
    sumsy_params.configure_sumsy_actors!(model)
    sumsy_params.distribute_wealth!(model)
end

# distribute_wealth functions

function distribute_equal!(model::ABM, initial_gi_wealth::Real, initial_non_gi_wealth::Real)
    for actor in allagents(model)
        if is_gi_eligible(actor)
            book_asset!(get_balance(actor), SUMSY_DEP, initial_gi_wealth)
        else
            book_asset!(get_balance(actor), SUMSY_DEP, initial_non_gi_wealth)
        end
    end
end

function concentrate_wealth!(model::ABM, initial_gi_wealth::Real, initial_non_gi_wealth::Real)
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

# configure_sumsy_actors! functions

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

# Debt based with borrowing

struct DebtBasedParams{C <: FixedDecimal} <: MonetaryModelParams
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