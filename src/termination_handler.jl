abstract type TerminationHandler end

struct NoTerminationHandler <: TerminationHandler end

function initialize_termination_handler!(model::ABM, termination_handler::NoTerminationHandler) end

"""
    FlaggedTerminationHandler

Used to flag when termination is imminent and terminate upon a secondary condition.
* `set_flag` - function that determines if the termination flag needs to be set. Must return a Bool.
* `terminate` - function that indicates the simulation should be terminated, if the flag is set. Must return a Bool.
"""
struct FlaggedTerminationHandler <: TerminationHandler
    set_flag::Function
    terminate::Function
end

function check_termination(model::ABM)
    if model.set_flag(model)
        model.termination_flag = true
    end

    if model.termination_flag && model.terminate(model)
        model.run_steps = model.step
    end
end

function initialize_termination_handler!(model::ABM, termination_handler::FlaggedTerminationHandler)
    properties = abmproperties(model)

    properties[:set_flag] = termination_handler.set_flag
    properties[:terminate] = termination_handler.terminate
    properties[:termination_flag] = false
    add_model_behavior!(model, check_termination)
end