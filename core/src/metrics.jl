# Aggregate metrics: Gini, mean/total/min/max, and percentile shares.
#
# Metric values are Float64 currency units for the result surface; the
# simulation itself stays in integer Money.

const SHARE_FRACTIONS = (0.01, 0.10, 0.50, 0.90, 0.99, 0.999)

function total_wealth(state::SimState)::Money
    total = MONEY_ZERO
    for i in eachindex(state.wealth)
        is_alive(state, i) && (total += state.wealth[i])
    end
    return total
end

function mean_wealth(state::SimState)::Float64
    n = alive_count(state)
    n == 0 && return 0.0
    return currency(total_wealth(state)) / Float64(n)
end

function minmax_wealth(state::SimState)
    n = alive_count(state)
    n == 0 && return (0.0, 0.0)

    min_value = typemax(Int64)
    max_value = typemin(Int64)
    for i in eachindex(state.wealth)
        is_alive(state, i) || continue
        v = state.wealth[i].value
        v < min_value && (min_value = v)
        v > max_value && (max_value = v)
    end
    return (Float64(min_value) / SCALE, Float64(max_value) / SCALE)
end

function gini_of_sorted(values::Vector{Float64})::Float64
    n = length(values)
    n <= 1 && return 0.0

    total = 0.0
    weighted = 0.0
    for (i, value) in enumerate(values)
        total += value
        weighted += Float64(i) * value
    end
    total <= 0.0 && return 0.0
    return (2.0 * weighted) / (Float64(n) * total) - (Float64(n) + 1.0) / Float64(n)
end

function cumulative_shares(values::Vector{Float64})::Vector{Float64}
    out = zeros(Float64, 6)
    total = sum(values)
    n = length(values)
    (total > 0.0 && n > 0) || return out

    accumulated = 0.0
    previous = 0
    for k in 1:6
        idx = min(n, max(0, round(Int, SHARE_FRACTIONS[k] * n)))
        for j in (previous + 1):idx
            accumulated += values[j]
        end
        out[k] = accumulated / total
        previous = idx
    end
    return out
end

function _alive_values!(scratch::Vector{Float64}, source::Vector{Money},
                        state::SimState)
    m = 0
    for i in eachindex(source)
        if is_alive(state, i)
            m += 1
            scratch[m] = Float64(source[i].value)
        end
    end
    return m
end

"""
    record_income!(results, state, index)

Record the income accumulated since the previous recording, then reset the
accumulator. This mirrors the legacy `data_income` register.
"""
function record_income!(results::ResultBuffers, state::SimState, index::Int)
    m = alive_count(state)
    base = (index - 1) * 6

    if m == 0
        results.income_gini[index] = -1.0
        for k in 1:6
            results.income_shares[base + k] = -1.0
        end
        return results
    end

    income_values = Vector{Float64}(undef, m)
    _alive_values!(income_values, state.data_income_used ?
                   state.data_income : state.income, state)
    sort!(income_values)

    if sum(income_values) <= 0.0
        results.income_gini[index] = -1.0
        for k in 1:6
            results.income_shares[base + k] = -1.0
        end
    else
        results.income_gini[index] = gini_of_sorted(income_values)
        income_shares = cumulative_shares(income_values)
        for k in 1:6
            results.income_shares[base + k] = income_shares[k]
        end
    end

    fill!(state.data_income, MONEY_ZERO)
    return results
end

"""
    record_wealth!(results, state, index, collected)

Record wealth aggregates and the period's tax / public-debt ledger.
"""
function record_wealth!(results::ResultBuffers, state::SimState, index::Int,
                        collected::Money)
    m = alive_count(state)
    base = (index - 1) * 6

    results.tax_collected[index] = currency(collected)
    results.tax_scale[index] = state.tax_scale
    results.government_debt[index] = currency(state.loan_circuit_active ?
                                              state.bank_reserve :
                                              state.government_debt)
    results.vat_collected[index] = currency(state.vat_collected)
    state.vat_collected = MONEY_ZERO

    total = total_wealth(state)
    book_debt = MONEY_ZERO
    for principal in state.loan_book_principal
        book_debt += principal
    end
    if book_debt == MONEY_ZERO
        for value in state.debt
            book_debt += value
        end
    end

    results.loan_debt[index] = currency(book_debt)
    results.loan_equity[index] = currency(state.bank_reserve)
    results.loan_issued[index] = currency(state.loan_issued)
    results.growth_ratio[index] = state.loan_growth
    results.profit_ratio[index] = state.loan_profit
    results.loan_ratio[index] = total.value > 0 ?
        100.0 * Float64(state.loan_issued.value) / Float64(total.value) : 0.0

    if m == 0
        results.gini[index] = 0.0
        results.mean[index] = 0.0
        results.total[index] = 0.0
        results.min[index] = 0.0
        results.max[index] = 0.0
        for k in 1:6
            results.shares[base + k] = 0.0
        end
        return results
    end

    wealth_values = Vector{Float64}(undef, m)
    _alive_values!(wealth_values, state.wealth, state)
    sort!(wealth_values)

    results.gini[index] = gini_of_sorted(wealth_values)
    results.mean[index] = sum(wealth_values) / Float64(m) / SCALE
    results.total[index] = sum(wealth_values) / SCALE
    results.min[index] = wealth_values[1] / SCALE
    results.max[index] = wealth_values[end] / SCALE

    shares = cumulative_shares(wealth_values)
    for k in 1:6
        results.shares[base + k] = shares[k]
    end
    return results
end

"""
    record_period!(results, state, index, collected)

Record both income and wealth metrics at the current state. Used by the
custom-run ABI hook.
"""
function record_period!(results::ResultBuffers, state::SimState, index::Int,
                        collected::Money)
    record_income!(results, state, index)
    record_wealth!(results, state, index, collected)
    return results
end

export SHARE_FRACTIONS, total_wealth, mean_wealth, minmax_wealth
export gini_of_sorted, cumulative_shares, record_income!, record_wealth!, record_period!
