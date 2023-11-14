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
                                make_sumsy_actors! = make_sumsy_actors!,
                                distribute_wealth! = distributed ? equal_wealth_distribution! : concentrated_wealth_distribution!)
    transaction_params = StandardYardSaleParams(eligible_actors + non_eligible_actors,
                                                num_transactions:num_transactions,
                                                0.2:0.2:0.2,
                                                0)
    model_adaptations = isnothing(model_adaptation) ? Vector{Function}() : Vector{Function}([model_adaptation])

    run_sumsy_simulation(sumsy, sim_params, transaction_params, sumsy_params, model_adaptations)
end

function run_consumer_supplier_simulation(sumsy::SuMSy,
                                            sim_length::Int = 150;
                                            consumers_per_supplier::Int = 100,
                                            demand::Int = 1,
                                            price::Real = 1,
                                            suppliers_gi_eligible = false)
    sim_params = SimParams(sim_length * sumsy.interval, sumsy.interval)

    gi_eligible_types = suppliers_gi_eligible ? [:supplier, :consumer] : [:consumer]
    sumsy_params = SuMSyParams(telo(sumsy), make_sumsy_actors! = model -> typed_gi_actors!(model, gi_eligible_types))
    consumer_supply_params = FixedConsumerSupplyParams(1, consumers_per_supplier, demand, price)

    return run_sumsy_simulation(sumsy, sim_params, consumer_supply_params, sumsy_params)
end