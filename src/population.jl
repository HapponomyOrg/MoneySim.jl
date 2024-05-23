using Agents

abstract type PopulationParams end

struct FixedPopulationParams <: PopulationParams
end

function initialize_population_model!(model::ABM, population_params::FixedPopulationParams)
end

struct PopulationVectorParams <: PopulationParams
    population_vector::Vector{<: Integer}
    adjustment_interval::Integer
    adjust_population!::Function
    create_actor!::Function
    PopulationVectorParams(population_vector::Vector{<: Integer},
                            adjustment_interval::Integer;
                            adjust_population!::Function = adjust_vector_population!,
                            create_actor! = MonetaryActor) =
                                    new(population_vector,
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
                    transfer_asset!(model, dead_agent, heir, asset_value(get_balance(dead_agent), asset))
                end

                for liability in liabilities(dead_balance)
                    transfer_liability!(model, dead_agent, heir, liability_value(get_balance(dead_agent), liability))
                end

                remove_agent!(dead_agent, model)
            end
        end
    end
end

function create_sumsy_actor!(model::ABM)
    return make_single_sumsy!(model, model.sumsy, MonetaryActor(model), initialize = false)
end

struct DynamicPopulationParams <: PopulationParams
    adjustment_interval::Integer
    supplemental_initialisation!::Union{Nothing, Function}
    adjust_population!::Function
    DynamicPopulationParams(adjustment_interval::Integer,
                            supplemental_initialisation!::Union{Nothing, Function} = nothing,
                            adjust_population!::Function = adjust_vector_population!) =
                                new(supplemental_initialisation!,
                                    adjustment_interval,
                                    adjust_population!)
end

function initialize_population_model!(model::ABM, population_params::DynamicPopulationParams)
    properties = abmproperties(model)
    properties[:adjustment_interval] = population_params.adjustment_interval
    add_model_behavior!(model, population_params.adjust_population!)

    if !isnothing(population_params.supplemental_initialisation!)
        population_params.supplemental_initialisation!(model)
    end
end