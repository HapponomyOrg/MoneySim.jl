NO_TERMINATION = NoTerminationHandler()

function terminate_at_end_interval(model::ABM)
    return interval_complete(model, model.step)
end

TERMINATE_WHEN_ONE_NON_BROKE = FlaggedTerminationHandler(one_non_broke, terminate_at_end_interval)