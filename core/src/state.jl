# Concrete simulation state and result buffers.
#
# State is structure-of-arrays: one vector per actor-level quantity. This is
# the layout the wasm ABI will read and write through scalar accessors.

mutable struct SimState
    n::Int
    wealth::Vector{Money}
    income::Vector{Money}
    expenses::Vector{Money}
    step_income::Vector{Money}
    step_expenses::Vector{Money}
    data_income::Vector{Money}
    data_income_used::Bool
    vat_eligible::Vector{Money}
    vat_deduction::Vector{Money}
    debt::Vector{Money}
    tax_owed::Vector{Money}
    notional::Vector{Money}
    notional_active::Bool
    gi_eligible::Vector{UInt8}
    alive::Vector{UInt8}
    age_type::Vector{UInt8}
    actor_role::Vector{UInt8}
    supplier_of::Vector{Int}
    last_adjustment::Vector{Int}
    sumsy_gi_steps::Vector{Int}
    sumsy_gi_booked::Vector{Money}
    tax_slices::Int
    tax_scale::Float64
    tax_accum::Money
    government_debt::Money
    vat_collected::Money
    gdp_factor::Float64
    gdp_target::Money
    loan_pool::Money
    loan_initialized::Bool
    loan_collapsed::Bool
    loan_book_principal::Vector{Money}
    loan_book_cycles::Vector{Int}
    loan_book_rate::Vector{Int64}
    loan_book_installment::Vector{Money}
    bank_reserve::Money
    loan_circuit_active::Bool
    loan_issued::Money
    loan_growth::Float64
    loan_profit::Float64
    scratch::Vector{Float64}
    income_scratch::Vector{Float64}
end

function SimState(n::Integer = 0)
    count = Int(n)
    gi_eligible = Vector{UInt8}(undef, count)
    alive = Vector{UInt8}(undef, count)
    age_type = Vector{UInt8}(undef, count)
    actor_role = Vector{UInt8}(undef, count)
    supplier_of = Vector{Int}(undef, count)
    last_adjustment = Vector{Int}(undef, count)
    for i in 1:count
        gi_eligible[i] = UInt8(1)
        alive[i] = UInt8(1)
        age_type[i] = UInt8(0)
        actor_role[i] = UInt8(0)
        supplier_of[i] = 0
        last_adjustment[i] = 0
    end
    return SimState(count,
                    fill(MONEY_ZERO, count),
                    fill(MONEY_ZERO, count),
                    fill(MONEY_ZERO, count),
                    fill(MONEY_ZERO, count),
                    fill(MONEY_ZERO, count),
                    fill(MONEY_ZERO, count),
                    false,
                    fill(MONEY_ZERO, count),
                    fill(MONEY_ZERO, count),
                    fill(MONEY_ZERO, count),
                    fill(MONEY_ZERO, count),
                    fill(MONEY_ZERO, count),
                    false,
                    gi_eligible,
                    alive,
                    age_type,
                    actor_role,
                    supplier_of,
                    last_adjustment,
                    fill(0, count),
                    fill(MONEY_ZERO, count),
                    0,
                    1.0,
                    MONEY_ZERO,
                    MONEY_ZERO,
                    MONEY_ZERO,
                    1.0,
                    MONEY_ZERO,
                    MONEY_ZERO,
                    false,
                    false,
                    Vector{Money}(undef, 0),
                    Vector{Int}(undef, 0),
                    Vector{Int64}(undef, 0),
                    Vector{Money}(undef, 0),
                    MONEY_ZERO,
                    false,
                    MONEY_ZERO,
                    0.0,
                    0.0,
                    Vector{Float64}(undef, count),
                    Vector{Float64}(undef, count))
end

@inline is_alive(state::SimState, i::Int) = state.alive[i] == UInt8(1)

function alive_count(state::SimState)
    count = 0
    for i in eachindex(state.alive)
        state.alive[i] == UInt8(1) && (count += 1)
    end
    return count
end

function _age_type_from_shares(count::Int, shares::Vector{Int64})
    types = Vector{UInt8}(undef, count)
    if isempty(shares) || length(shares) < 3
        for i in 1:count
            types[i] = UInt8(0)
        end
        return types
    end

    child_share = max(shares[1], 0)
    adult_share = max(shares[2], 0)
    elder_share = max(shares[3], 0)
    total = child_share + adult_share + elder_share
    if total <= 0
        for i in 1:count
            types[i] = UInt8(0)
        end
        return types
    end

    children = round(Int, count * child_share / total)
    elders = round(Int, count * elder_share / total)
    children = clamp(children, 0, count)
    elders = clamp(elders, 0, count - children)
    adults = count - children - elders
    index = 1
    for _ in 1:children
        types[index] = UInt8(0)
        index += 1
    end
    for _ in 1:adults
        types[index] = UInt8(1)
        index += 1
    end
    for _ in 1:elders
        types[index] = UInt8(2)
        index += 1
    end
    return types
end

function _assign_roles!(state::SimState, cfg::TransactionConfig)
    for i in 1:state.n
        state.actor_role[i] = UInt8(0)
        state.supplier_of[i] = 0
    end
    cfg.model === TransactionModel.CONSUMER_SUPPLIER || return nothing
    cfg.suppliers > 0 || return nothing

    suppliers = min(cfg.suppliers, state.n)
    per_supplier = max(cfg.consumers_per_supplier, 0)
    index = 1
    for supplier in 1:suppliers
        state.actor_role[supplier] = UInt8(1)
    end
    index = suppliers + 1
    consumers = suppliers * per_supplier
    for k in 1:consumers
        index > state.n && break
        supplier = div(k - 1, max(per_supplier, 1)) + 1
        state.actor_role[index] = UInt8(2)
        state.supplier_of[index] = supplier
        index += 1
    end
    return nothing
end

function reset_state!(state::SimState, cfg::SimConfig)
    n = cfg.population.count

    if state.n != n
        resize!(state.wealth, n)
        resize!(state.income, n)
        resize!(state.expenses, n)
        resize!(state.step_income, n)
        resize!(state.step_expenses, n)
        resize!(state.data_income, n)
        resize!(state.vat_eligible, n)
        resize!(state.vat_deduction, n)
        resize!(state.debt, n)
        resize!(state.tax_owed, n)
        resize!(state.notional, n)
        resize!(state.gi_eligible, n)
        resize!(state.alive, n)
        resize!(state.age_type, n)
        resize!(state.actor_role, n)
        resize!(state.supplier_of, n)
        resize!(state.last_adjustment, n)
        resize!(state.sumsy_gi_steps, n)
        resize!(state.sumsy_gi_booked, n)
        resize!(state.scratch, n)
        resize!(state.income_scratch, n)
        state.n = n
    end

    fill!(state.income, MONEY_ZERO)
    fill!(state.expenses, MONEY_ZERO)
    fill!(state.step_income, MONEY_ZERO)
    fill!(state.step_expenses, MONEY_ZERO)
    fill!(state.data_income, MONEY_ZERO)
    fill!(state.vat_eligible, MONEY_ZERO)
    fill!(state.vat_deduction, MONEY_ZERO)
    fill!(state.debt, MONEY_ZERO)
    fill!(state.tax_owed, MONEY_ZERO)
    fill!(state.last_adjustment, 0)
    fill!(state.sumsy_gi_steps, 0)
    fill!(state.sumsy_gi_booked, MONEY_ZERO)
    if isempty(cfg.tax.notional)
        fill!(state.notional, MONEY_ZERO)
        state.notional_active = false
    else
        for i in 1:min(n, length(cfg.tax.notional))
            state.notional[i] = cfg.tax.notional[i]
        end
        for i in (length(cfg.tax.notional) + 1):n
            state.notional[i] = MONEY_ZERO
        end
        state.notional_active = true
    end
    if state.notional_active
        # Legacy initialises `vat_eligible` from the projected income assigned
        # at setup (`init_income!`), so the first VAT window sees it too.
        for i in 1:n
            state.vat_eligible[i] = state.notional[i]
        end
    end
    state.tax_slices = 0
    state.tax_scale = 1.0
    state.tax_accum = MONEY_ZERO
    state.government_debt = cfg.government.initial_debt
    state.vat_collected = MONEY_ZERO
    state.gdp_factor = 1.0
    state.gdp_target = cfg.gdp.per_capita * n
    state.loan_pool = MONEY_ZERO
    state.loan_initialized = false
    state.loan_collapsed = false
    empty!(state.loan_book_principal)
    empty!(state.loan_book_cycles)
    empty!(state.loan_book_rate)
    empty!(state.loan_book_installment)
    state.bank_reserve = MONEY_ZERO
    state.loan_circuit_active = cfg.money.model === MoneyModel.LOAN_CIRCUIT
    state.loan_issued = MONEY_ZERO
    state.loan_growth = 0.0
    state.loan_profit = 0.0

    ages = _age_type_from_shares(n, cfg.population.age_shares)
    for i in 1:n
        state.alive[i] = UInt8(1)
        state.age_type[i] = ages[i]
    end

    _assign_roles!(state, cfg.transactions)
    typed_suppliers = cfg.transactions.model === TransactionModel.CONSUMER_SUPPLIER &&
                      !cfg.transactions.suppliers_gi_eligible &&
                      cfg.transactions.suppliers > 0

    if isempty(cfg.population.gi_eligible)
        for i in 1:n
            state.gi_eligible[i] = typed_suppliers && state.actor_role[i] == UInt8(1) ?
                UInt8(0) : UInt8(1)
        end
    else
        copyto!(state.gi_eligible, cfg.population.gi_eligible)
    end

    if cfg.wealth.distribution === WealthDistribution.EQUAL
        for i in 1:n
            state.wealth[i] = cfg.wealth.equal_amount
        end
    elseif cfg.wealth.distribution === WealthDistribution.CUSTOM
        fill!(state.wealth, MONEY_ZERO)
        for i in 1:min(n, length(cfg.wealth.custom))
            state.wealth[i] = cfg.wealth.custom[i]
        end
    else # CONCENTRATED
        fill!(state.wealth, MONEY_ZERO)
        state.wealth[1] = cfg.wealth.equal_amount * n
    end

    return state
end

mutable struct ResultBuffers
    gini::Vector{Float64}
    mean::Vector{Float64}
    total::Vector{Float64}
    min::Vector{Float64}
    max::Vector{Float64}
    income_gini::Vector{Float64}
    shares::Vector{Float64}
    income_shares::Vector{Float64}
    tax_collected::Vector{Float64}
    tax_scale::Vector{Float64}
    government_debt::Vector{Float64}
    vat_collected::Vector{Float64}
    loan_debt::Vector{Float64}
    loan_equity::Vector{Float64}
    loan_issued::Vector{Float64}
    growth_ratio::Vector{Float64}
    profit_ratio::Vector{Float64}
    loan_ratio::Vector{Float64}
end

function ResultBuffers(count::Integer)
    n = Int(count)
    return ResultBuffers(fill(0.0, n), fill(0.0, n), fill(0.0, n),
                         fill(0.0, n), fill(0.0, n), fill(0.0, n),
                         fill(0.0, n * 6), fill(0.0, n * 6), fill(0.0, n),
                         fill(1.0, n), fill(0.0, n), fill(0.0, n),
                         fill(0.0, n), fill(0.0, n), fill(0.0, n),
                         fill(0.0, n), fill(0.0, n), fill(0.0, n))
end

"""
    SimResult

Per-record aggregate series. `periods` is the number of recorded rows; each
vector has that length, and `shares` has `periods * 6` entries.
"""
struct SimResult
    periods::Int
    gini::Vector{Float64}
    mean::Vector{Float64}
    total::Vector{Float64}
    min::Vector{Float64}
    max::Vector{Float64}
    income_gini::Vector{Float64}
    shares::Vector{Float64}
    income_shares::Vector{Float64}
    tax_collected::Vector{Float64}
    tax_scale::Vector{Float64}
    government_debt::Vector{Float64}
    vat_collected::Vector{Float64}
    loan_debt::Vector{Float64}
    loan_equity::Vector{Float64}
    loan_issued::Vector{Float64}
    growth_ratio::Vector{Float64}
    profit_ratio::Vector{Float64}
    loan_ratio::Vector{Float64}
end

function SimResult(buffers::ResultBuffers, periods::Int)
    return SimResult(periods, buffers.gini, buffers.mean, buffers.total,
                     buffers.min, buffers.max, buffers.income_gini,
                     buffers.shares, buffers.income_shares,
                     buffers.tax_collected, buffers.tax_scale,
                     buffers.government_debt, buffers.vat_collected,
                     buffers.loan_debt, buffers.loan_equity,
                     buffers.loan_issued, buffers.growth_ratio,
                     buffers.profit_ratio, buffers.loan_ratio)
end

export SimState, ResultBuffers, SimResult, reset_state!, is_alive, alive_count
