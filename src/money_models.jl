using EconoSim
using Random
using Agents
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

"""
SuMSyParams constructor

SuMSyParams can only be used in conjunction with a SuMSy model.
Must be called after initialize_transaction_model!
"""
struct SuMSyParams{C <: FixedDecimal} <: MonetaryModelParams{C}
    initial_gi_wealth::C
    initial_non_gi_wealth::C
    make_sumsy_actors!::Function
    distribute_wealth!::Function
    SuMSyParams(initial_gi_wealth::Real,
                initial_non_gi_wealth::Real = 0;
                make_sumsy_actors!::Function = mixed_actors!,
                distribute_wealth!::Function = equal_wealth_distribution!) = new{Currency}(initial_gi_wealth,
                                                                                        initial_non_gi_wealth,
                                                                                        make_sumsy_actors!,
                                                                                        distribute_wealth!)
end

function equal_wealth_distribution!(model::ABM, sumsy_params::SuMSyParams)
    for actor in allagents(model)
        if is_gi_eligible(actor)
            book_asset!(get_balance(actor), SUMSY_DEP, sumsy_params.initial_gi_wealth)
        else
            book_asset!(get_balance(actor), SUMSY_DEP, sumsy_params.initial_non_gi_wealth)
        end
    end
end

function concentrated_wealth_distribution!(model::ABM, sumsy_params::SuMSyParams)
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
                                    sumsy_params::SuMSyParams)
    sumsy_params.make_sumsy_actors!(model)
    sumsy_params.distribute_wealth!(model, sumsy_params)
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
end