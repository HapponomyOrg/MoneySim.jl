function run_sumsy_simulation(sumsy::SuMSy;
                                eligible_actors::Int = 1000,
                                non_eligible_actors::Int = 0,
                                num_transactions::Int = 200,
                                period_length::Int = sumsy.interval,
                                sim_length::Int = 150,
                                distributed::Bool = true,
                                model_adaptation::Union{Function, Nothing} = nothing)
    sim_params = SimParams(true, sim_length * period_length, period_length, num_transactions:num_transactions)

    initial_wealth = telo(sumsy)

    if non_eligible_actors > 0
        initial_wealth *= eligible_actors / (eligible_actors + non_eligible_actors)
    end


    sumsy_params = SuMSyParams(sumsy.income.guaranteed_income,
                                sumsy.demurrage.dem_free,
                                sumsy.demurrage.dem_tiers,
                                sumsy.transactional,
                                eligible_actors,
                                initial_wealth,
                                non_eligible_actors,
                                initial_wealth,
                                distributed)
    transaction_params = YardSaleParams(0.2:0.2:0.2, 0)
    model_adaptations = isnothing(model_adaptation) ? Vector{Function}() : Vector{Function}([model_adaptation])

    run_sumsy_simulation(sim_params, sumsy_params, transaction_params, model_adaptations)
end