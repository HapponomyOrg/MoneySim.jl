# Transaction models.
#
# Two models share the same bookkeeping: yard-sale transfers between random
# actors, and the consumer–supplier model from paper 2 (each consumer pays a
# fixed demand × price to its supplier every step). Transfers conserve money;
# winners book step income and losers book step expenses.

const BROKE_THRESHOLD = Money(100) # 0.01 currency in scaled units

"""
    register_income!(state)

Move the step's market income into the tax window and data accumulators,
mirroring MoneySim's `register_income_and_expenses!`.
"""
function register_income!(state::SimState)
    state.data_income_used = true
    for i in eachindex(state.wealth)
        is_alive(state, i) || continue
        income = state.step_income[i]
        state.income[i] += income
        state.data_income[i] += income
        state.vat_eligible[i] += income
        state.expenses[i] += state.step_expenses[i]
        state.step_income[i] = MONEY_ZERO
        state.step_expenses[i] = MONEY_ZERO
    end
    return nothing
end

function _broke_threshold(rate::Int64)
    rate <= 0 && return BROKE_THRESHOLD
    increment = Money(100) # 0.01, the legacy increment
    threshold = MONEY_ZERO
    for _ in 1:100
        threshold += increment
        apply_rate(threshold, rate) != MONEY_ZERO && return threshold + increment
    end
    return BROKE_THRESHOLD
end

function _non_broke_candidates(state::SimState, threshold::Money)
    candidates = Int[]
    for i in 1:state.n
        is_alive(state, i) || continue
        state.wealth[i] >= threshold && push!(candidates, i)
    end
    return candidates
end

function _rand_non_broke(state::SimState, rng::Rng, threshold::Money)
    state.n > 0 || return 0
    for _ in 1:64
        idx = rand_index(rng, state.n)
        if is_alive(state, idx) && state.wealth[idx] >= threshold
            return idx
        end
    end
    return 0
end

function coinflip_prob(asset_value_1::Float64, asset_value_2::Float64,
                       wealth_advantage::Float64,
                       average_wealth::Float64)::Float64
    average = average_wealth > 0.0 ? average_wealth : 1.0
    raw_bias = wealth_advantage * (asset_value_1 - asset_value_2) / average
    bias = min(max(raw_bias, -1.0), 1.0)
    return (1.0 + bias) / 2.0
end

"""
    yardsale_transfer!(state, cfg, money, rng, average_wealth, period) -> Money

Execute one yard-sale transfer. Returns the amount moved (zero if the draw was
invalid or the transfer was blocked by the minimum balance).
"""
function _yardsale_at!(state::SimState, cfg::TransactionConfig,
                       money::MoneyConfig, rng::Rng,
                       average_wealth::Float64, period::Int,
                       i::Int, j::Int)
    if money.transactional
        adjust_transactional!(state, i, period, money)
        adjust_transactional!(state, j, period, money)
    end

    av1 = max(Int64(0), state.wealth[i].value)
    av2 = max(Int64(0), state.wealth[j].value)
    min_balance = min(av1, av2)

    rate_amount = apply_rate(Money(min_balance), cfg.transfer_rate)
    amount = max(min(min_balance, cfg.minimal_transfer.value), rate_amount.value)
    amount <= 0 && return MONEY_ZERO

    probability_first = coinflip_prob(Float64(av1) / SCALE,
                                      Float64(av2) / SCALE,
                                      cfg.wealth_advantage, average_wealth)
    moved = Money(amount)

    if rand_unit(rng) < probability_first
        if cfg.allow_negative || state.wealth[j] >= moved
            state.wealth[i] = state.wealth[i] + moved
            state.step_income[i] += moved
            state.wealth[j] -= moved
            state.step_expenses[j] += moved
        end
    else
        if cfg.allow_negative || state.wealth[i] >= moved
            state.wealth[j] = state.wealth[j] + moved
            state.step_income[j] += moved
            state.wealth[i] -= moved
            state.step_expenses[i] += moved
        end
    end

    return moved
end

function yardsale_transfer!(state::SimState, cfg::TransactionConfig,
                            money::MoneyConfig, rng::Rng,
                            average_wealth::Float64, period::Int)
    threshold = _broke_threshold(cfg.transfer_rate)
    i = _rand_non_broke(state, rng, threshold)
    j = _rand_non_broke(state, rng, threshold)
    (i == j || i == 0 || j == 0) && return MONEY_ZERO
    return _yardsale_at!(state, cfg, money, rng, average_wealth, period, i, j)
end

"""
    transactions_step!(state, cfg, rng)

Run the configured number of yard-sale transfers for one simulation step.
"""
function transactions_step!(state::SimState, cfg::TransactionConfig,
                            money::MoneyConfig, rng::Rng, period::Int)
    (cfg.enabled && cfg.transactions_per_step > 0) || return nothing
    average = mean_wealth(state)
    for _ in 1:cfg.transactions_per_step
        yardsale_transfer!(state, cfg, money, rng, average, period)
    end
    return nothing
end

"""
    gdp_transactions_step!(state, cfg, gdp, money, rng, period)

Run yard-sale transfers until the period's volume target is met.
"""
function gdp_transactions_step!(state::SimState, cfg::TransactionConfig,
                                gdp::GdpConfig, money::MoneyConfig,
                                rng::Rng, period::Int)
    n = alive_count(state)
    n > 0 || return nothing

    target = state.gdp_target.value
    target <= 0 && return nothing

    average = mean_wealth(state)
    threshold = _broke_threshold(cfg.transfer_rate)
    candidates = _non_broke_candidates(state, threshold)
    volume = Int64(0)
    guard = n * 50
    while volume < target && length(candidates) > 1 && guard > 0
        count = length(candidates)
        idx1 = rand_index(rng, count)
        idx2 = rand_index(rng, count)
        if idx1 == idx2
            if idx2 == 1
                idx2 += 1
            elseif idx2 == count
                idx2 -= 1
            elseif rand_unit(rng) < 0.5
                idx2 += 1
            else
                idx2 -= 1
            end
        end

        i = candidates[idx1]
        j = candidates[idx2]
        rand_unit(rng) # legacy transfer-rate draw; the rate is fixed here
        amount = _yardsale_at!(state, cfg, money, rng, average, period, i, j)
        volume += amount.value

        if state.wealth[i] < threshold
            filter!(x -> x != i, candidates)
        end
        if state.wealth[j] < threshold
            filter!(x -> x != j, candidates)
        end
        guard -= 1
    end

    if gdp.growth_ppm != 0
        growth = Float64(gdp.growth_ppm) / (12.0 * Float64(RATE_SCALE))
        state.gdp_target = Money(round(Int64, Float64(state.gdp_target.value) * (1.0 + growth)))
        state.gdp_factor *= 1.0 + growth
    end
    return nothing
end

"""
    consumer_supplier_step!(state, cfg, money, period)

Paper-2 consumer–supplier model. Every consumer pays `demand × price` to its
supplier, reducing demand until the payment is affordable.
"""
function consumer_supplier_step!(state::SimState, cfg::TransactionConfig,
                                 money::MoneyConfig, period::Int)
    cfg.model === TransactionModel.CONSUMER_SUPPLIER || return nothing
    cfg.demand > 0 || return nothing
    cfg.price > MONEY_ZERO || return nothing

    for i in eachindex(state.wealth)
        (is_alive(state, i) && state.actor_role[i] == UInt8(2)) || continue
        supplier = state.supplier_of[i]
        (1 <= supplier <= state.n && is_alive(state, supplier)) || continue

        money.transactional && adjust_transactional!(state, i, period, money)
        available = state.wealth[i]

        units = cfg.demand
        while units > 0 && Money(units) * cfg.price.value > available
            units -= 1
        end
        units <= 0 && continue

        amount = Money(units) * cfg.price.value
        amount <= MONEY_ZERO && continue
        amount > available && continue

        state.wealth[i] -= amount
        state.step_expenses[i] += amount
        state.wealth[supplier] = state.wealth[supplier] + amount
        state.step_income[supplier] += amount
    end
    return nothing
end

function transactions_step!(state::SimState, cfg::TransactionConfig,
                            gdp::GdpConfig, money::MoneyConfig, rng::Rng,
                            period::Int)
    if cfg.model === TransactionModel.CONSUMER_SUPPLIER
        cfg.enabled || return nothing
        return consumer_supplier_step!(state, cfg, money, period)
    end
    if gdp.enabled
        return gdp_transactions_step!(state, cfg, gdp, money, rng, period)
    end
    cfg.enabled || return nothing
    return transactions_step!(state, cfg, money, rng, period)
end

export BROKE_THRESHOLD, coinflip_prob, yardsale_transfer!, transactions_step!
export gdp_transactions_step!, consumer_supplier_step!, register_income!
