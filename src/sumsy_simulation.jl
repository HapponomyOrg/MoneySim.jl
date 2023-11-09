function run_sumsy_simulation(sumsy::SuMSy;
                                eligible_actors::Int = 1000,
                                non_eligible_actors::Int = 0,
                                num_transactions::Int = 200,
                                period_length::Int = sumsy.interval,
                                sim_length::Int = 150,
                                distributed::Bool = true,
                                model_adaptation::Union{Function, Nothing} = nothing)
    sim_params = SimParams(sim_length * period_length,
                            period_length)

    initial_wealth = telo(sumsy)

    if non_eligible_actors > 0
        make_sumsy_actors! = model -> mixed_actors!(model, eligible_actors)
    else
        make_sumsy_actors! = mixed_actors!
    end

    if non_eligible_actors > 0
        initial_wealth *= eligible_actors / (eligible_actors + non_eligible_actors)
    end


    sumsy_params = SuMSyParams(initial_wealth,
                                initial_wealth,
                                initial_wealth,
                                distributed)
    transaction_params = StandardYardSaleParams(eligible_actors + non_eligible_actors,
                                                num_transactions:num_transactions,
                                                0.2:0.2:0.2,
                                                0)
    model_adaptations = isnothing(model_adaptation) ? Vector{Function}() : Vector{Function}([model_adaptation])

    run_sumsy_simulation(sumsy, sim_params, transaction_params, sumsy_params, model_adaptations)
end