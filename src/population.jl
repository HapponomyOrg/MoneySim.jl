using Agents
import Base.Callable

abstract type PopulationParams end

struct FixedPopulationParams <: PopulationParams
    create_actor!::Function
    FixedPopulationParams(create_actor! = create_monetary_actor) = new(create_actor!)
end

function initialize_population_model!(model::ABM, population_params::FixedPopulationParams)
    abmproperties(model)[:create_actor!] = population_params.create_actor!
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

struct VaryingPopulationParams <: PopulationParams
    create_actor!::Function
    adjust_population!::Function
end

function initialize_population_model!(model::ABM, population_params::VaryingPopulationParams)
    abmproperties(model)[:create_actor!] = population_params.create_actor!
    add_model_behavior!(model, population_params.adjust_population!)
end