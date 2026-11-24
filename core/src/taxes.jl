# Taxes, redistribution, and the government deficit.
#
# Phase 4 adds the progressive income tax with optional target-revenue scaling
# and monthly slice collection. The wealth levy remains the flat path.

function _add_remainder!(state::SimState, amount::Money)
    remaining = amount.value
    remaining <= 0 && return
    for i in eachindex(state.wealth)
        is_alive(state, i) || continue
        state.wealth[i] += Money(1)
        remaining -= 1
        remaining <= 0 && break
    end
    return
end

"""
    redistribute!(state, amount, recipient, recipient_actor)

Redistribute collected tax. `DESTROY` extinguishes it; `ONE_ACTOR` sends it to
one actor; `FIRST_N` splits it among the first N alive actors; `EVERYONE`
splits it equally among all alive actors.
"""
function redistribute!(state::SimState, amount::Money,
                       recipient::TaxRecipient.Kind, recipient_actor::Int)
    amount <= MONEY_ZERO && return nothing
    recipient === TaxRecipient.DESTROY && return nothing

    if recipient === TaxRecipient.ONE_ACTOR
        if recipient_actor >= 1 && recipient_actor <= state.n &&
           is_alive(state, recipient_actor)
            state.wealth[recipient_actor] += amount
        end
        return nothing
    end

    if recipient === TaxRecipient.FIRST_N
        targets = min(max(recipient_actor, 0), alive_count(state))
        targets <= 0 && return nothing
        share, remainder = split_amount(amount, targets)
        seen = 0
        for i in eachindex(state.wealth)
            is_alive(state, i) || continue
            seen += 1
            seen > targets && break
            state.wealth[i] += share
        end
        _add_remainder!(state, remainder)
        return nothing
    end

    targets = alive_count(state)
    targets <= 0 && return nothing
    share, remainder = split_amount(amount, targets)
    for i in eachindex(state.wealth)
        is_alive(state, i) || continue
        state.wealth[i] += share
    end
    _add_remainder!(state, remainder)
    return nothing
end

"""
    bracket_tax(taxable, brackets, rates) -> Money

Progressive marginal tax. `brackets[i]` is the cumulative upper bound of band
`i`; the last band is unbounded. `rates[i]` is its ppm rate.
"""
function bracket_tax(taxable::Money, brackets::Vector{Money},
                     rates::Vector{Int64})::Money
    bands = min(length(brackets), length(rates))
    bands == 0 && return MONEY_ZERO

    remaining = taxable
    tax = MONEY_ZERO
    previous = MONEY_ZERO
    for band in 1:bands
        upper = band == bands ? typemax(Money) : brackets[band]
        width = upper - previous
        in_band = min(max(remaining, MONEY_ZERO), width)
        tax += apply_rate(in_band, rates[band])
        remaining -= in_band
        previous = upper
    end
    return max(tax, MONEY_ZERO)
end

"""
    bracket_base!(bases, taxable, brackets)

Add `taxable` to the per-band aggregate bases, mirroring the legacy
`create_tax_base`.
"""
function bracket_base!(bases::Vector{Money}, taxable::Money,
                       brackets::Vector{Money})
    bands = length(bases)
    remaining = max(taxable, MONEY_ZERO)
    previous = MONEY_ZERO
    for band in 1:bands
        remaining <= MONEY_ZERO && break
        upper = band == bands ? typemax(Money) : brackets[min(band, length(brackets))]
        width = upper == typemax(Money) ? typemax(Money) : upper - previous
        amount = width == typemax(Money) ? remaining : min(remaining, width)
        bases[band] += amount
        remaining -= amount
        previous = upper
    end
    return bases
end

function _projected_revenue(bases::Vector{Money}, rates::Vector{Int64})
    revenue = MONEY_ZERO
    n = min(length(bases), length(rates))
    for i in 1:n
        revenue += apply_rate(bases[i], rates[i])
    end
    return revenue
end

"""
    scale_brackets_exact(bases, brackets, rates, target) -> (rates, scale)

Scale every non-edge band by `overall = target / projected`, round each rate to
two decimals, and clamp to [0.1%, 95%]. This matches the paper reference runs:
a8 scales down (0.4185 → 10/17/19/21%) and c3 scales up into the 95% ceiling.
The returned `scale` is the rounded overall ratio.
"""
function scale_brackets_exact(bases::Vector{Money}, brackets::Vector{Money},
                              rates::Vector{Int64}, target::Money)
    n = min(length(bases), length(rates))
    n == 0 && return copy(rates), 1.0

    projected = _projected_revenue(bases, rates)
    projected <= MONEY_ZERO && return copy(rates), 1.0

    overall = round(Float64(target.value) / Float64(projected.value), digits = 2)
    applied = copy(rates)
    for i in 1:n
        value = Float64(applied[i]) / Float64(RATE_SCALE)
        if value > 0.001 && value < 0.95
            scaled = max(0.001, min(0.95, round(value * overall, digits = 2)))
            applied[i] = round(Int64, scaled * RATE_SCALE)
        end
    end

    return applied, overall
end

"""
    tax_step_wealth!(state, cfg, period) -> Money
"""
function tax_step_wealth!(state::SimState, cfg::TaxConfig, period::Int)
    (cfg.interval > 0 && cfg.rate > 0) || return MONEY_ZERO
    mod(period, cfg.interval) == 0 || return MONEY_ZERO

    collected = MONEY_ZERO
    for i in eachindex(state.wealth)
        is_alive(state, i) || continue
        state.wealth[i] > MONEY_ZERO || continue
        levy = min(apply_rate(state.wealth[i], cfg.rate), state.wealth[i])
        state.wealth[i] -= levy
        collected += levy
    end
    state.tax_scale = 1.0
    redistribute!(state, collected, cfg.recipient, cfg.recipient_actor)
    return collected
end

@inline function _income_base(state::SimState, i::Int)
    if state.notional_active
        return Money(round(Int64, Float64(state.notional[i].value) * state.gdp_factor))
    end
    return state.income[i]
end

"""
    tax_step_income!(state, cfg, period) -> Money

Assess at the start of every tax window, then collect one slice per period.
The assessed base is the window's accumulated market income. If
`scale_to_target` is set, the bracket rates are scaled (and clamped to
[0.1%, 95%]) so the assessed total meets `target_revenue`; the recorded scale
is the raw target/projected ratio.
"""
function tax_step_income!(state::SimState, cfg::TaxConfig, period::Int)
    (cfg.interval > 0 && !isempty(cfg.bracket_rates)) || return MONEY_ZERO

    if mod(period - 1, cfg.interval) == 0
        bands = length(cfg.bracket_rates)
        bases = fill(MONEY_ZERO, bands)
        for i in eachindex(state.wealth)
            is_alive(state, i) || continue
            bracket_base!(bases, _income_base(state, i), cfg.brackets)
        end

        applied = cfg.bracket_rates
        if cfg.scale_to_target && cfg.target_revenue > MONEY_ZERO
            applied, scale = scale_brackets_exact(bases, cfg.brackets,
                                                   cfg.bracket_rates,
                                                   cfg.target_revenue)
            state.tax_scale = scale
        else
            state.tax_scale = 1.0
        end

        for i in eachindex(state.wealth)
            is_alive(state, i) || continue
            base = _income_base(state, i)
            state.tax_owed[i] = if base > MONEY_ZERO
                owed = bracket_tax(base, cfg.brackets, applied) - state.vat_deduction[i]
                max(owed, MONEY_ZERO)
            else
                MONEY_ZERO
            end
            state.vat_deduction[i] = MONEY_ZERO
            state.income[i] = MONEY_ZERO
        end
        state.notional_active = false
        state.tax_slices = cfg.interval
    end

    state.tax_slices > 0 || return MONEY_ZERO

    collected = MONEY_ZERO
    for i in eachindex(state.wealth)
        is_alive(state, i) || continue
        owed = state.tax_owed[i]
        owed > MONEY_ZERO || continue
        slice = div(owed, state.tax_slices)
        slice > MONEY_ZERO || continue
        levy = cfg.allow_negative ? slice : min(slice, max(state.wealth[i], MONEY_ZERO))
        if levy > MONEY_ZERO
            state.wealth[i] -= levy
            state.tax_owed[i] -= levy
            collected += levy
        end
    end
    state.tax_slices -= 1

    redistribute!(state, collected, cfg.recipient, cfg.recipient_actor)
    return collected
end

"""
    tax_step_demurrage!(state, cfg, money, period) -> Money

The demurrage tax is assessed on `balance - demurrage_free` using the same
brackets and target scaling as the income tax. It is collected in slices and
does not reduce the income base.
"""
function tax_step_demurrage!(state::SimState, cfg::TaxConfig,
                             money::MoneyConfig, period::Int)
    (cfg.interval > 0 && !isempty(cfg.bracket_rates)) || return MONEY_ZERO

    if mod(period - 1, cfg.interval) == 0
        bands = length(cfg.bracket_rates)
        bases = fill(MONEY_ZERO, bands)
        for i in eachindex(state.wealth)
            is_alive(state, i) || continue
            bracket_base!(bases, _demurrage_base(state, money, i), cfg.brackets)
        end

        applied = cfg.bracket_rates
        if cfg.scale_to_target && cfg.target_revenue > MONEY_ZERO
            applied, scale = scale_brackets_exact(bases, cfg.brackets,
                                                   cfg.bracket_rates,
                                                   cfg.target_revenue)
            state.tax_scale = scale
        else
            state.tax_scale = 1.0
        end

        for i in eachindex(state.wealth)
            is_alive(state, i) || continue
            taxable = _demurrage_base(state, money, i)
            state.tax_owed[i] = if taxable > MONEY_ZERO
                owed = bracket_tax(taxable, cfg.brackets, applied) - state.vat_deduction[i]
                max(owed, MONEY_ZERO)
            else
                MONEY_ZERO
            end
            state.vat_deduction[i] = MONEY_ZERO
        end
        state.tax_slices = cfg.interval
    end

    state.tax_slices > 0 || return MONEY_ZERO

    collected = MONEY_ZERO
    for i in eachindex(state.wealth)
        is_alive(state, i) || continue
        owed = state.tax_owed[i]
        owed > MONEY_ZERO || continue
        slice = div(owed, state.tax_slices)
        slice > MONEY_ZERO || continue
        levy = cfg.allow_negative ? slice : min(slice, max(state.wealth[i], MONEY_ZERO))
        if levy > MONEY_ZERO
            state.wealth[i] -= levy
            state.tax_owed[i] -= levy
            collected += levy
        end
    end
    state.tax_slices -= 1

    redistribute!(state, collected, cfg.recipient, cfg.recipient_actor)
    return collected
end

@inline function _demurrage_base(state::SimState, money::MoneyConfig, i::Int)
    free = isempty(money.typed_demurrage_free) ? money.demurrage_free :
        money.typed_demurrage_free[clamp(Int(state.age_type[i]) + 1, 1, 3)]
    return max(state.wealth[i] - free, MONEY_ZERO)
end

"""
    vat_step!(state, cfg, tax, period) -> Money

Collect VAT on income accumulated since the previous collection. The headline
rate `r` charges `r / (1 + r)` of the eligible amount, mirroring
`scale_vat` in the legacy tax scheme. VAT is redistributed to the configured
recipients and, when `deduct_from_taxes` is set, reduces the next assessment.
"""
function vat_step!(state::SimState, cfg::VatConfig, tax::TaxConfig,
                   period::Int)
    (cfg.enabled && cfg.interval > 0) || return MONEY_ZERO
    mod(period, cfg.interval) == 0 || return MONEY_ZERO

    headline = Float64(cfg.rate) / Float64(RATE_SCALE)
    scale = headline / (1.0 + headline)

    collected = MONEY_ZERO
    for i in eachindex(state.wealth)
        is_alive(state, i) || continue
        base = state.vat_eligible[i]
        due = Money(round(Int64, Float64(base.value) * scale))
        if !tax.allow_negative
            due = min(due, max(state.wealth[i], MONEY_ZERO))
        end
        due = max(due, MONEY_ZERO)
        if due > MONEY_ZERO
            state.wealth[i] -= due
            cfg.deduct_from_taxes && (state.vat_deduction[i] += due)
            collected += due
        end
        state.vat_eligible[i] = MONEY_ZERO
    end

    redistribute!(state, collected, cfg.recipient, cfg.recipient_actor)
    state.vat_collected = saturating_add(state.vat_collected, collected)
    return collected
end

"""
    tax_step!(state, cfg, money, period) -> Money
"""
function tax_step!(state::SimState, cfg::TaxConfig, money::MoneyConfig,
                   period::Int)
    if cfg.kind === TaxKind.WEALTH
        return tax_step_wealth!(state, cfg, period)
    elseif cfg.kind === TaxKind.INCOME
        return tax_step_income!(state, cfg, period)
    elseif cfg.kind === TaxKind.DEMURRAGE
        return tax_step_demurrage!(state, cfg, money, period)
    end
    state.tax_scale = 1.0
    return MONEY_ZERO
end

tax_step!(state::SimState, cfg::TaxConfig, period::Int) =
    tax_step!(state, cfg, MoneyConfig(), period)

"""
    government_step!(state, government, tax, collected)

Create the deficit when spending exceeds collected tax, add it to public debt,
and distribute it to the tax recipients.
"""
function government_step!(state::SimState, government::GovernmentConfig,
                          tax::TaxConfig, collected::Money)
    government.enabled || return nothing
    government.deficit_spending || return nothing
    government.expenses > collected || return nothing

    deficit = government.expenses - collected
    state.government_debt += deficit
    redistribute!(state, deficit, tax.recipient, tax.recipient_actor)
    return nothing
end

export redistribute!, bracket_tax, tax_step_wealth!, tax_step_income!
export tax_step_demurrage!, vat_step!, tax_step!, government_step!
