# Money-model steps.
#
# `FIXED` leaves balances alone (paper 3's fixed-money scenarios). `SUMSY`
# applies guaranteed income and demurrage. `DEBT_BASED` uses homogeneous
# interest or the post-Keynesian bank. `LOAN_CIRCUIT` implements paper 1 in
# growth and loan-rate modes, with optional per-cycle random draws.

function _typed_value(values::Vector{Money}, index::Int, fallback::Money)
    isempty(values) && return fallback
    length(values) >= 3 || return fallback
    return values[clamp(index, 1, 3)]
end

@inline _age_slot(state::SimState, i::Int) = Int(state.age_type[i]) + 1

"""
    adjust_transactional!(state, i, period, cfg)

Apply the guaranteed income and demurrage accrued since actor `i`'s previous
adjustment. Transactional accounts are adjusted on every touch, not on the
periodic interval.
"""
function adjust_transactional!(state::SimState, i::Int, period::Int,
                               cfg::MoneyConfig)
    cfg.transactional || return nothing
    (1 <= i <= state.n) || return nothing
    is_alive(state, i) || return nothing

    elapsed = period - state.last_adjustment[i]
    elapsed <= 0 && return nothing

    guaranteed_income = _typed_value(cfg.typed_guaranteed_income,
                                     _age_slot(state, i), cfg.guaranteed_income)
    demurrage_free = _typed_value(cfg.typed_demurrage_free,
                                  _age_slot(state, i), cfg.demurrage_free)
    sumsy = SuMSy(guaranteed_income, cfg.demurrage, demurrage_free)
    gi, demurrage = calculate_adjustments(
        state.wealth[i], sumsy, state.gi_eligible[i] == UInt8(1),
        demurrage_free, cfg.interval, elapsed, false)
    state.wealth[i] += gi - demurrage
    state.last_adjustment[i] = period
    return nothing
end

"""
    pending_sumsy_assets(state, i, period, cfg) -> Money

The balance an actor would have after applying accrued SuMSy adjustments,
without mutating the state.
"""
function pending_sumsy_assets(state::SimState, i::Int, period::Int,
                              cfg::MoneyConfig)::Money
    cfg.transactional || return state.wealth[i]
    elapsed = period - state.last_adjustment[i]
    elapsed <= 0 && return state.wealth[i]

    guaranteed_income = _typed_value(cfg.typed_guaranteed_income,
                                     _age_slot(state, i), cfg.guaranteed_income)
    demurrage_free = _typed_value(cfg.typed_demurrage_free,
                                  _age_slot(state, i), cfg.demurrage_free)
    sumsy = SuMSy(guaranteed_income, cfg.demurrage, demurrage_free)
    gi, demurrage = calculate_adjustments(
        state.wealth[i], sumsy, state.gi_eligible[i] == UInt8(1),
        demurrage_free, cfg.interval, elapsed, false)
    return state.wealth[i] + gi - demurrage
end

"""
    sumsy_step!(state, cfg, period)

Apply demurrage and guaranteed income every `cfg.interval` steps. Transactional
accounts are adjusted on transactions instead, so the periodic step is skipped.
"""
function sumsy_step!(state::SimState, cfg::MoneyConfig, period::Int)
    cfg.transactional && return nothing
    (cfg.interval > 0 && mod(period, cfg.interval) == 0) || return nothing

    for i in eachindex(state.wealth)
        is_alive(state, i) || continue
        guaranteed_income = _typed_value(cfg.typed_guaranteed_income,
                                         _age_slot(state, i),
                                         cfg.guaranteed_income)
        demurrage_free = _typed_value(cfg.typed_demurrage_free,
                                      _age_slot(state, i), cfg.demurrage_free)
        sumsy = SuMSy(guaranteed_income, cfg.demurrage, demurrage_free)
        gi, demurrage = calculate_adjustments(
            state.wealth[i], sumsy, state.gi_eligible[i] == UInt8(1),
            demurrage_free, cfg.interval, cfg.interval, false)
        state.wealth[i] += gi - demurrage
    end
    return nothing
end

"""
    debt_step!(state, cfg, period)

Homogeneous interest model: with no designated bank, every balance grows by the
interest rate each interval.
"""
function debt_step!(state::SimState, cfg::MoneyConfig, period::Int)
    (cfg.interval > 0 && mod(period, cfg.interval) == 0) || return nothing
    cfg.interest_rate == 0 && return nothing

    for i in eachindex(state.wealth)
        is_alive(state, i) || continue
        state.wealth[i] += apply_rate(state.wealth[i], cfg.interest_rate)
    end
    return nothing
end

function _lend_to_poorest!(state::SimState, bank::Int, targets::Int,
                           amount::Money)
    (targets > 0 && amount > MONEY_ZERO) || return nothing
    available = alive_count(state) - (is_alive(state, bank) ? 1 : 0)
    targets = min(targets, available)
    targets <= 0 && return nothing

    chosen = fill(false, state.n)
    share, remainder = split_amount(amount, targets)

    for k in 1:targets
        best = 0
        for i in eachindex(state.wealth)
            is_alive(state, i) || continue
            i == bank && continue
            chosen[i] && continue
            if best == 0 || state.wealth[i] < state.wealth[best]
                best = i
            end
        end
        best == 0 && break
        chosen[best] = true
        add = share + (k <= remainder.value ? Money(1) : MONEY_ZERO)
        state.wealth[best] += add
        state.debt[best] += add
    end
    return nothing
end

"""
    bank_step!(state, money, bank)

One post-Keynesian bank step: interest to the bank, principal repayment
(money destruction), then new lending to the poorest actors (money creation).
"""
function bank_step!(state::SimState, money::MoneyConfig, bank::BankConfig)
    bank.enabled || return nothing
    index = bank.actor_index
    (1 <= index <= state.n && is_alive(state, index)) || return nothing

    if money.interest_rate != 0
        for i in eachindex(state.wealth)
            (is_alive(state, i) && i != index && state.debt[i] > MONEY_ZERO) || continue
            interest = min(apply_rate(state.debt[i], money.interest_rate),
                           max(state.wealth[i], MONEY_ZERO))
            if interest > MONEY_ZERO
                state.wealth[i] -= interest
                state.wealth[index] += interest
            end
        end
    end

    if bank.repayment_rate > 0
        for i in eachindex(state.wealth)
            (is_alive(state, i) && i != index && state.debt[i] > MONEY_ZERO) || continue
            repayment = min(apply_rate(state.debt[i], bank.repayment_rate),
                            max(state.wealth[i], MONEY_ZERO))
            if repayment > MONEY_ZERO
                state.wealth[i] -= repayment
                state.debt[i] -= repayment
            end
        end
    end

    _lend_to_poorest!(state, index, bank.lending_targets, bank.lending_amount)
    return nothing
end

"""
    _paper_pool_debit(pool, payment, remaining, rate) -> Money

Legacy keeps one aggregate Currency balance and applies `balance += -debit`
for every loan in sequence, rounding the whole balance each time. Reproducing
that balance-dependent rounding is what keeps long loan-rate runs on the same
trajectory as the paper.
"""
function _paper_pool_debit(pool::Money, payment::Money, remaining::Money,
                           rate::Int64)::Money
    interest = Float64(remaining.value) / Float64(SCALE) *
               (Float64(rate) / Float64(RATE_SCALE))
    debit = Float64(payment.value) / Float64(SCALE) + interest
    value = Float64(pool.value) / Float64(SCALE) - debit
    return Money(_clamp_int64(value * Float64(SCALE)))
end

function _paper_loan(pool::Money, loan_rate::Int64)::Money
    pool <= MONEY_ZERO && return MONEY_ZERO
    rate = Float64(loan_rate) / Float64(RATE_SCALE)
    rate >= 1.0 && return MONEY_ZERO
    required = (Float64(pool.value) / Float64(SCALE) / (1.0 - rate)) * rate
    required = round(required, digits = 2)
    required <= 0.0 && return MONEY_ZERO
    return Money(round(Int64, required * Float64(SCALE)))
end

function _paper_installment(principal::Money, maturity::Int)
    maturity = max(maturity, 1)
    q, r = divrem(principal.value, maturity)
    2r > maturity && return Money(q + 1)
    2r == maturity && return Money(iseven(q) ? q : q + 1)
    return Money(q)
end

function _resync_pro_rata!(state::SimState, old_total::Money, new_total::Money)
    old_total == new_total && return nothing
    n = alive_count(state)
    n == 0 && return nothing

    if new_total <= MONEY_ZERO
        for i in eachindex(state.wealth)
            state.wealth[i] = MONEY_ZERO
        end
        return nothing
    end

    if old_total <= MONEY_ZERO
        share, remainder = split_amount(new_total, n)
        given = 0
        for i in eachindex(state.wealth)
            is_alive(state, i) || continue
            state.wealth[i] = share
            if given < remainder.value
                state.wealth[i] += Money(1)
                given += 1
            end
        end
        return nothing
    end

    total = MONEY_ZERO
    for i in eachindex(state.wealth)
        is_alive(state, i) || continue
        scaled = Float64(state.wealth[i].value) * Float64(new_total.value) /
                 Float64(old_total.value)
        state.wealth[i] = Money(_clamp_int64(round(scaled)))
        total += state.wealth[i]
    end

    remainder = new_total.value - total.value
    step = remainder > 0 ? Int64(1) : Int64(-1)
    index = 1
    while remainder != 0 && index <= state.n
        if is_alive(state, index)
            state.wealth[index] += Money(step)
            remainder -= step
        end
        index += 1
    end
    return nothing
end

@inline function _rate_percent(ppm_rate::Int64)::Float64
    return 100.0 * Float64(ppm_rate) / Float64(RATE_SCALE)
end

@inline function _clamp_int64(value::Float64)::Int64
    value >= Float64(typemax(Int64)) && return typemax(Int64)
    value <= Float64(typemin(Int64)) && return typemin(Int64)
    return round(Int64, value)
end

"""
    loan_circuit_step!(state, money, loan, period, rng)

Paper-1 loan circuit. In growth mode every balance accrues growth and debt
accrues profit. In loan-rate mode the aggregate loan book is amortised and new
loans are created from the remaining pool. `random_mode` draws the growth rate
or loan rate and the maturity per cycle, matching `simulate_random_g` and
`simulate_random_LR`.
"""
function loan_circuit_step!(state::SimState, money::MoneyConfig,
                            loan::LoanCircuitConfig, period::Int, rng::Rng)
    loan.enabled || return nothing

    if loan.mode == 0
        if !state.loan_initialized
            for i in eachindex(state.wealth)
                is_alive(state, i) || continue
                state.debt[i] = max(state.wealth[i], MONEY_ZERO)
            end
            state.loan_initialized = true
        end

        growth = money.interest_rate
        profit = loan.profit_rate
        if loan.random_mode === LoanRandomMode.GROWTH
            growth = rand_between(rng, loan.min_value, loan.max_value)
            profit = growth + loan.relative_profit
            loan.no_loss && (profit = max(profit, Int64(0)))
        end

        created_total = MONEY_ZERO
        if profit != 0
            for i in eachindex(state.wealth)
                (is_alive(state, i) && state.debt[i] > MONEY_ZERO) || continue
                converted = apply_rate(state.debt[i], profit)
                state.bank_reserve = saturating_add(state.bank_reserve, converted)
                state.debt[i] = saturating_add(state.debt[i], converted)
            end
        end

        if growth != 0
            for i in eachindex(state.wealth)
                is_alive(state, i) || continue
                created = apply_rate(state.wealth[i], growth)
                state.wealth[i] = saturating_add(state.wealth[i], created)
                state.debt[i] = saturating_add(state.debt[i], created)
                created_total = saturating_add(created_total, created)
            end
        end

        state.loan_issued = created_total
        state.loan_growth = _rate_percent(growth)
        state.loan_profit = _rate_percent(profit)
        return nothing
    end

    # Loan-rate mode: aggregate pool + amortisation book.
    old_pool = total_wealth(state)
    loan_rate = money.interest_rate
    if loan.random_mode === LoanRandomMode.LOAN_RATE
        loan_rate = rand_between(rng, loan.min_value, loan.max_value)
    end

    new_maturity = loan.maturity
    if loan.random_mode === LoanRandomMode.LOAN_RATE &&
       loan.max_maturity > loan.min_maturity
        new_maturity = Int(rand_between(rng, loan.min_maturity, loan.max_maturity))
    end

    if !state.loan_initialized
        initial_rate = loan.random_mode === LoanRandomMode.LOAN_RATE ?
            loan.relative_profit : loan.profit_rate
        push!(state.loan_book_principal, old_pool)
        push!(state.loan_book_cycles, max(new_maturity, 1))
        push!(state.loan_book_rate, initial_rate)
        push!(state.loan_book_installment,
              _paper_installment(old_pool, max(new_maturity, 1)))
        state.loan_initialized = true
    end

    pool = old_pool
    for l in eachindex(state.loan_book_principal)
        remaining = state.loan_book_principal[l]
        cycles = state.loan_book_cycles[l]
        payment = cycles <= 1 ? remaining : state.loan_book_installment[l]
        pool = _paper_pool_debit(pool, payment, remaining,
                                 state.loan_book_rate[l])
        state.loan_book_principal[l] = remaining - payment
        state.loan_book_cycles[l] = cycles - 1
    end

    while !isempty(state.loan_book_cycles) && state.loan_book_cycles[1] <= 0
        popfirst!(state.loan_book_principal)
        popfirst!(state.loan_book_cycles)
        popfirst!(state.loan_book_rate)
        popfirst!(state.loan_book_installment)
    end

    new_loan = _paper_loan(pool, loan_rate)
    growth_fraction = old_pool.value > 0 ?
        Float64(pool.value + new_loan.value - old_pool.value) /
        Float64(old_pool.value) : 0.0

    profit = loan.profit_rate
    if loan.random_mode === LoanRandomMode.LOAN_RATE
        profit = round(Int64, growth_fraction * RATE_SCALE) + loan.relative_profit
        loan.no_loss && (profit = max(profit, Int64(0)))
    end

    if new_loan > MONEY_ZERO
        pool = saturating_add(pool, new_loan)
        push!(state.loan_book_principal, new_loan)
        push!(state.loan_book_cycles, max(new_maturity, 1))
        push!(state.loan_book_rate, profit)
        push!(state.loan_book_installment,
              _paper_installment(new_loan, max(new_maturity, 1)))
    end

    book_debt = MONEY_ZERO
    for principal in state.loan_book_principal
        book_debt = saturating_add(book_debt, principal)
    end
    state.bank_reserve = book_debt - pool

    state.loan_pool = pool
    state.loan_collapsed = pool <= MONEY_ZERO
    state.loan_issued = new_loan
    state.loan_growth = 100.0 * growth_fraction
    state.loan_profit = _rate_percent(profit)
    _resync_pro_rata!(state, old_pool, pool)
    return nothing
end

"""
    step_money!(state, cfg, bank, loan, period, rng)

Dispatch to the configured money model.
"""
function step_money!(state::SimState, cfg::MoneyConfig, bank::BankConfig,
                     loan::LoanCircuitConfig, period::Int, rng::Rng)
    if cfg.model === MoneyModel.SUMSY
        sumsy_step!(state, cfg, period)
    elseif cfg.model === MoneyModel.DEBT_BASED
        if bank.enabled
            bank_step!(state, cfg, bank)
        else
            debt_step!(state, cfg, period)
        end
    elseif cfg.model === MoneyModel.LOAN_CIRCUIT
        loan_circuit_step!(state, cfg, loan, period, rng)
    end
    return nothing
end

export sumsy_step!, debt_step!, bank_step!, loan_circuit_step!, step_money!
export adjust_transactional!, pending_sumsy_assets, register_income!
