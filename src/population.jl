using Agents
import Base.Callable

abstract type PopulationParams end

struct FixedPopulationParams{F <: Function} <: PopulationParams
    population::Integer
    create_actor!::F
    FixedPopulationParams(;population::Integer,
                            create_actor! = create_monetary_actor) = new{typeof(create_actor!)}(population, create_actor!)
end

function initialize_population_model!(model::ABM, population_params::FixedPopulationParams)
    abmproperties(model)[:create_actor!] = population_params.create_actor!

    for _ in 1:population_params.population
        add_actor!(model, population_params.create_actor!(model))
    end
end

struct PopulationVectorParams{FA <: Function, FC <: Function} <: PopulationParams
    population_vector::Vector{<: Integer}
    adjustment_interval::Integer
    adjust_population!::FA
    create_actor!::FC
    PopulationVectorParams(population_vector::Vector{<: Integer},
                            adjustment_interval::Integer;
                            adjust_population!::Function = adjust_vector_population!,
                            create_actor! = MonetaryActor) =
                                    new{typeof(adjust_population!), typeof(create_actor!)}(population_vector,
                                        adjustment_interval,
                                        adjust_population!,
                                        create_actor!)
end

function initialize_population_model!(model::ABM, population_params::PopulationVectorParams)
    properties = abmproperties(model)
    properties[:population_vector] = population_params.population_vector
    properties[:adjustment_interval] = population_params.adjustment_interval
    properties[:create_actor!] = population_params.create_actor!
    add_model_behavior!(model, population_params.adjust_population!)

    for _ in 1:population_params.population_vector[1]
        add_actor!(model, population_params.create_actor!(model))
    end
end

function adjust_vector_population!(model::ABM)
    interval = model.adjustment_interval
    population_vector = model.population_vector

    if model.step % interval == 0 && nagents(model) != population_vector[Int(round(model.step / interval))]
        population_adjustment = population_vector[Int(round(model.step / interval))] - nagents(model)

        if population_adjustment > 0
            create_actor! = model.create_actor!

            for _ in 1:population_adjustment
                agent = add_actor!(model, create_actor!(model))
                set_last_adjustment!(agent.balance, model.step)
            end
        else
            for _ in 1:abs(population_adjustment)
                dead_agent = random_agent(model)
                heir = random_agent(model)

                while dead_agent == heir
                    heir = random_agent(model)
                end

                dead_balance = get_balance(dead_agent)

                for asset in assets(dead_balance)
                    transfer_asset!(model, dead_agent, heir, asset, asset_value(get_balance(dead_agent), asset))
                end

                for liability in liabilities(dead_balance)
                    transfer_liability!(model, dead_agent, heir, liability, liability_value(get_balance(dead_agent), liability))
                end

                remove_agent!(dead_agent, model)
            end
        end
    end
end

"""
    TypedPopulationParams{FC <: Function}
    * num_actors::Int - The number of actors to be created for the simulation.
    * types::Dict{Symbol, Int} - A dictionary of age types and their respective percentages.
    * adjust_up::Symbol - THe symbol of the age type used if the number of actors needs to be adjusted up.
    * adjust_down::Symbol - The symbol of the age type used if the number of actors needs to be adjusted down.
    * create_actor!::FC - A function that creates an actor for the simulation.

    A struct that holds the parameters for creating a population of actors with different age types.
    The numbers in the types dictionary are scaled to the number of actual actors in the simulation.
    The scaled number of actors is adjusted up or down if the sum of the scaled numbers do not exactly match the number of actors.
"""
struct TypedPopulationParams{FC <: Function} <: PopulationParams
    num_actors::Int
    actor_types::Dict{Symbol, Float64}
    adjust_up::Symbol
    adjust_down::Symbol
    create_actor!::FC
    TypedPopulationParams(;num_actors::Int,
                            actor_types::Dict{Symbol, <:Real},
                            adjust_up::Symbol,
                            adjust_down::Symbol,
                            create_actor!::Function = create_monetary_actor) =
                                    new{typeof(create_actor!)}(num_actors,
                                                                actor_types,
                                                                adjust_up,
                                                                adjust_down,
                                                                create_actor!)
end

function initialize_population_model!(model::ABM, population_params::TypedPopulationParams)
    actor_percentages = population_params.actor_types
    actor_numbers = Dict{Symbol, Int}()
    num_actors = population_params.num_actors

    for (type, percentage) in actor_percentages
        actor_numbers[type] = Int(round(percentage * num_actors))
    end

    population = Int(sum(values(actor_numbers)))

    if population < num_actors
        actor_numbers[population_params.adjust_up] += num_actors - population
    elseif population > num_actors
        actor_numbers[population_params.adjust_down] -= population - num_actors
    end

    for (type, num) in actor_numbers
        for _ in 1:num
            add_type!(add_actor!(model, population_params.create_actor!(model)), type)
        end
    end
end

struct VaryingPopulationParams{FC <: Function, FA <: Function} <: PopulationParams
    initial_population::Integer
    create_actor!::FC
    adjust_population!::FA

    VaryingPopulationParams(initial_population::Integer,
                            create_actor! = MonetaryActor;
                            adjust_population! = adjust_vector_population!) =
                                    new{typeof(create_actor!), typeof(adjust_population!)}(initial_population,
                                        create_actor!,
                                        adjust_population!)
end

function initialize_population_model!(model::ABM, population_params::VaryingPopulationParams)
    abmproperties(model)[:create_actor!] = population_params.create_actor!
    add_model_behavior!(model, population_params.adjust_population!)

    for _ in 1:population_params.initial_population
        add_actor!(model, population_params.create_actor!(model))
    end
end