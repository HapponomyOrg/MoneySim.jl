using Agents

abstract type DataHandler end

# Interval data handler

struct IntervalDataHandler{F} <: DataHandler
    interval::Int
    actor_data_collectors::Vector
    model_data_collectors::Vector
    post_processing!::F

    function IntervalDataHandler(;interval::Int = 1,
                                    actor_data_collectors::Vector = [],
                                    model_data_collectors::Vector = [],
                                    post_processing!::Function = no_post_processing!)
        return new{typeof(post_processing!)}(interval,
                    actor_data_collectors,
                    model_data_collectors,
                    post_processing!)
    end 
end

function initialize_data_handler!(model::ABM, interval_data_handler::IntervalDataHandler)
    abmproperties(model)[:collection_interval] = interval_data_handler.interval

    return interval_complete, interval_data_handler.actor_data_collectors, interval_data_handler.model_data_collectors
end

post_process!(data_handler::IntervalDataHandler, actor_data, model_data) = data_handler.post_processing!(actor_data, model_data)

# Determine when to collect data

function interval_complete(model::ABM, step::Int)
    return mod(step, model.collection_interval) == 0
end