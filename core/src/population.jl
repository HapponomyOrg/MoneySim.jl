# Population dynamics.
#
# Fixed populations are the default. When demographic rates are configured,
# deaths zero a balance (money destruction), births append new children with
# `birth_wealth` (money creation), and aging advances child -> adult -> elder.
# GI eligibility can be set per age type.

function _grow_state!(state::SimState, new_n::Int)
    new_n <= state.n && return state
    old_n = state.n
    resize!(state.wealth, new_n)
    resize!(state.income, new_n)
    resize!(state.expenses, new_n)
    resize!(state.step_income, new_n)
    resize!(state.step_expenses, new_n)
    resize!(state.data_income, new_n)
    resize!(state.vat_eligible, new_n)
    resize!(state.vat_deduction, new_n)
    resize!(state.debt, new_n)
    resize!(state.tax_owed, new_n)
    resize!(state.gi_eligible, new_n)
    resize!(state.alive, new_n)
    resize!(state.age_type, new_n)
    resize!(state.actor_role, new_n)
    resize!(state.supplier_of, new_n)
    resize!(state.last_adjustment, new_n)
    resize!(state.scratch, new_n)
    resize!(state.income_scratch, new_n)

    for i in (old_n + 1):new_n
        state.wealth[i] = MONEY_ZERO
        state.income[i] = MONEY_ZERO
        state.expenses[i] = MONEY_ZERO
        state.step_income[i] = MONEY_ZERO
        state.step_expenses[i] = MONEY_ZERO
        state.data_income[i] = MONEY_ZERO
        state.vat_eligible[i] = MONEY_ZERO
        state.vat_deduction[i] = MONEY_ZERO
        state.debt[i] = MONEY_ZERO
        state.tax_owed[i] = MONEY_ZERO
        state.gi_eligible[i] = UInt8(1)
        state.alive[i] = UInt8(1)
        state.age_type[i] = UInt8(0)
        state.actor_role[i] = UInt8(0)
        state.supplier_of[i] = 0
        state.last_adjustment[i] = 0
    end
    state.n = new_n
    return state
end

function _choose_death_target(state::SimState)
    for actor_type in (UInt8(2), UInt8(1), UInt8(0))
        for i in eachindex(state.wealth)
            if is_alive(state, i) && state.age_type[i] == actor_type
                return i
            end
        end
    end
    return 0
end

@inline _gi_flag(flag::Bool) = flag ? UInt8(1) : UInt8(0)

"""
    population_step!(state, cfg, period, rng)

Apply aging, deaths, births, and typed GI eligibility for one step.
"""
function population_step!(state::SimState, cfg::PopulationConfig,
                          period::Int, rng::Rng)
    n_alive = alive_count(state)
    n_alive == 0 && return nothing

    if cfg.aging_interval > 0 && mod(period, cfg.aging_interval) == 0 &&
       cfg.aging_rate > 0
        threshold = Float64(cfg.aging_rate) / Float64(RATE_SCALE)
        for i in eachindex(state.wealth)
            is_alive(state, i) || continue
            if state.age_type[i] == UInt8(0) && rand_unit(rng) < threshold
                state.age_type[i] = UInt8(1)
            elseif state.age_type[i] == UInt8(1) && rand_unit(rng) < threshold
                state.age_type[i] = UInt8(2)
            end
        end
    end

    if cfg.death_rate > 0
        to_kill = div(n_alive * cfg.death_rate, RATE_SCALE)
        while to_kill > 0
            target = _choose_death_target(state)
            target == 0 && break
            state.alive[target] = UInt8(0)
            state.wealth[target] = MONEY_ZERO
            state.income[target] = MONEY_ZERO
            state.tax_owed[target] = MONEY_ZERO
            to_kill -= 1
        end
    end

    if cfg.birth_rate > 0
        remaining = alive_count(state)
        to_birth = div(remaining * cfg.birth_rate, RATE_SCALE)
        if to_birth > 0
            old_n = state.n
            _grow_state!(state, old_n + to_birth)
            for i in (old_n + 1):(old_n + to_birth)
                state.wealth[i] = cfg.birth_wealth
                state.income[i] = MONEY_ZERO
                state.age_type[i] = UInt8(0)
                state.alive[i] = UInt8(1)
                state.gi_eligible[i] = _gi_flag(cfg.gi_child)
            end
        end
    end

    if cfg.typed_gi
        for i in eachindex(state.wealth)
            is_alive(state, i) || continue
            actor_type = state.age_type[i]
            state.gi_eligible[i] = actor_type == UInt8(0) ? _gi_flag(cfg.gi_child) :
                                   actor_type == UInt8(1) ? _gi_flag(cfg.gi_adult) :
                                                            _gi_flag(cfg.gi_elder)
        end
    end

    return nothing
end

"""
    set_gi_eligible!(state, i, eligible)
"""
function set_gi_eligible!(state::SimState, i::Int, eligible::Bool)
    (1 <= i <= state.n) || return false
    state.gi_eligible[i] = eligible ? UInt8(1) : UInt8(0)
    return true
end

export population_step!, set_gi_eligible!
