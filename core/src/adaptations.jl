# Money injection, destruction, and equal-distribution adaptations.
#
# `TOTAL` splits a total amount equally among alive actors. `PER_ACTOR` applies
# the amount to each actor. `HALF_BALANCE` destroys half of each balance.
# `one_time` adaptations run at period 1 only.

function _sweep_inject!(state::SimState, amount::Money)
    targets = alive_count(state)
    targets <= 0 && return nothing
    share, remainder = split_amount(amount, targets)
    given = 0
    for i in eachindex(state.wealth)
        is_alive(state, i) || continue
        state.wealth[i] += share
        state.step_income[i] += share
        if given < remainder.value
            state.wealth[i] += Money(1)
            state.step_income[i] += Money(1)
            given += 1
        end
    end
    return nothing
end

function _sweep_destroy!(state::SimState, amount::Money)
    targets = alive_count(state)
    targets <= 0 && return nothing
    share, remainder = split_amount(amount, targets)
    given = 0
    for i in eachindex(state.wealth)
        is_alive(state, i) || continue
        take = min(share, max(state.wealth[i], MONEY_ZERO))
        state.wealth[i] -= take
        if given < remainder.value && state.wealth[i] > MONEY_ZERO
            extra = min(Money(1), state.wealth[i])
            state.wealth[i] -= extra
            given += 1
        end
    end
    return nothing
end

function _per_actor_inject!(state::SimState, amount::Money)
    amount <= MONEY_ZERO && return nothing
    for i in eachindex(state.wealth)
        is_alive(state, i) || continue
        state.wealth[i] += amount
        state.step_income[i] += amount
    end
    return nothing
end

function _per_actor_destroy!(state::SimState, amount::Money)
    amount <= MONEY_ZERO && return nothing
    for i in eachindex(state.wealth)
        is_alive(state, i) || continue
        state.wealth[i] -= min(amount, max(state.wealth[i], MONEY_ZERO))
    end
    return nothing
end

function _half_balance_destroy!(state::SimState)
    for i in eachindex(state.wealth)
        is_alive(state, i) || continue
        state.wealth[i] -= Money(div_round_nearest(max(state.wealth[i], MONEY_ZERO).value, 2))
    end
    return nothing
end

"""
    equal_money_distribution!(state, money, period)

Set every alive actor's balance to the mean of the SuMSy-adjusted money stock.
Any rounding remainder is destroyed, matching the legacy helper.
"""
function equal_money_distribution!(state::SimState, money::MoneyConfig,
                                   period::Int)
    targets = alive_count(state)
    targets <= 0 && return nothing

    total = MONEY_ZERO
    for i in eachindex(state.wealth)
        is_alive(state, i) || continue
        total += pending_sumsy_assets(state, i, period, money)
    end
    share = Money(div_round_nearest(total.value, targets))

    for i in eachindex(state.wealth)
        is_alive(state, i) || continue
        state.wealth[i] = share
    end
    return nothing
end

"""
    adaptations_step!(state, cfg, money, period)
"""
function adaptations_step!(state::SimState, cfg::AdaptationConfig,
                           money::MoneyConfig, period::Int)
    if cfg.inject_mode !== AdaptationMode.NONE &&
       (!cfg.inject_one_time || period == 1)
        due = cfg.inject_one_time ? period == 1 :
              (cfg.inject_interval > 0 && mod(period, cfg.inject_interval) == 0)
        if due
            if cfg.inject_mode === AdaptationMode.PER_ACTOR
                _per_actor_inject!(state, cfg.inject_amount)
            else
                _sweep_inject!(state, cfg.inject_amount)
            end
        end
    end

    if cfg.destroy_mode !== AdaptationMode.NONE &&
       (!cfg.destroy_one_time || period == 1)
        due = cfg.destroy_one_time ? period == 1 :
              (cfg.destroy_interval > 0 && mod(period, cfg.destroy_interval) == 0)
        if due
            if cfg.destroy_mode === AdaptationMode.HALF_BALANCE
                _half_balance_destroy!(state)
            elseif cfg.destroy_mode === AdaptationMode.PER_ACTOR
                _per_actor_destroy!(state, cfg.destroy_amount)
            else
                _sweep_destroy!(state, cfg.destroy_amount)
            end
        end
    end

    if cfg.equal_distribution
        interval = cfg.equal_interval > 0 ? cfg.equal_interval : money.interval
        if interval > 0 && mod(period, interval) == 0
            equal_money_distribution!(state, money, period)
        end
    end
    return nothing
end

export adaptations_step!, equal_money_distribution!
