# Paper adapter — one scenario manifest, two backends.
#
# `backend = :legacy` runs the pre-refactor Agents.jl/FixedPointDecimals
# implementation in `MoneySim`; `backend = :core` runs `MoneySimCore` with the
# same scenario parameters. The purpose is the before/after comparison, not
# paper parity: both sides use the same seed and scale.
#
# Paper 3 is captured at a reduced scale by default (1,000 actors × 10 years)
# so a live legacy baseline stays practical. Override with
# `PAPER3_BASELINE_ACTORS` / `PAPER3_BASELINE_YEARS` for a full-scale capture.

using MoneySim
import EconoSim
import EconoSimCore
import MoneySimCore

const EC = EconoSimCore
const MC = MoneySimCore

const PAPER_FIXTURES_DIR = joinpath(@__DIR__, "fixtures")
const PAPER_BASELINE_PATH = joinpath(PAPER_FIXTURES_DIR, "baseline.toml")

struct Paper1Result
    length::Int
    debt_ratio_pct::Union{Nothing,Float64}
    growth_ratio_pct::Union{Nothing,Float64}
    finite::Bool
end

struct Paper2Result
    money_stock::Float64
    max_money_stock::Float64
    min_money_stock::Float64
end

struct Paper2ConsumerResult
    supplier_balance::Float64
end

struct Paper3Result
    gini_wealth::Float64
    gini_income::Float64
    money_stock::Float64
    public_debt::Float64
    tax_collected::Float64
    tax_scale::Union{Nothing,Float64}
    top10_share::Float64
    bottom50_share::Float64
    income_top10_share::Float64
    income_bottom50_share::Float64
end

baseline_paper3_actors() =
    parse(Int, get(ENV, "PAPER3_BASELINE_ACTORS", "1000"))

baseline_paper3_years() =
    parse(Int, get(ENV, "PAPER3_BASELINE_YEARS", "10"))

# ---------------------------------------------------------------------------
# Paper 1 — post-Keynesian loan circuit
# ---------------------------------------------------------------------------

function _paper1_legacy(scenario)
    params = scenario.params
    data = if scenario.kind === :fixed_g
        simulate_fixed_g(; params...)
    elseif scenario.kind === :fixed_lr
        simulate_fixed_LR(; params...)
    elseif scenario.kind === :random_g
        simulate_random_g(; params...)
    elseif scenario.kind === :random_lr
        simulate_random_LR(; params...)
    else
        error("unknown paper 1 scenario kind: $(scenario.kind)")
    end

    finite = all(x -> isfinite(Float64(x)), debt_ratio(data)) &&
             all(x -> isfinite(Float64(x)), growth_ratio(data))

    if scenario.kind === :fixed_g || scenario.kind === :fixed_lr
        return Paper1Result(length(data),
                            Float64(last(debt_ratio(data))),
                            Float64(last(growth_ratio(data))),
                            finite)
    end
    return Paper1Result(length(data), nothing, nothing, finite)
end

function _paper1_core(scenario)
    params = scenario.params
    cycles = Int(params.cycles)
    maturity = Int(get(params, :m, get(params, :max_m, 20)))
    random_mode = MC.LoanRandomMode.FIXED
    min_value = 0.0
    max_value = 0.0
    min_maturity = 1
    max_maturity = 1
    relative_profit = 0.0
    no_loss = get(params, :no_loss, true)

    if scenario.kind === :fixed_g
        mode = 0
        rate = params.g
        profit = params.p
    elseif scenario.kind === :fixed_lr
        mode = 1
        rate = params.LR
        profit = params.p
    elseif scenario.kind === :random_g
        mode = 0
        rate = 0.0
        profit = 0.0
        random_mode = MC.LoanRandomMode.GROWTH
        min_value = params.min_g
        max_value = params.max_g
        relative_profit = params.relative_p
    elseif scenario.kind === :random_lr
        mode = 1
        rate = 0.0
        profit = 0.0
        random_mode = MC.LoanRandomMode.LOAN_RATE
        min_value = params.min_LR
        max_value = params.max_LR
        min_maturity = Int(params.min_m)
        max_maturity = Int(params.max_m)
        relative_profit = params.relative_p
    else
        error("unknown paper 1 scenario kind: $(scenario.kind)")
    end

    actors = 100
    # The paper runs M0 = 1,000,000. Ratios are scale-invariant, and the
    # scaled-Int64 core cannot represent the paper's m30 stable trajectory
    # (it reaches ~10^26 currency). Compare at a scaled M0 instead.
    m0 = 10_000
    money = MC.MoneyConfig(
        model = MC.MoneyModel.LOAN_CIRCUIT,
        interval = 1,
        guaranteed_income = EC.MONEY_ZERO,
        demurrage = EC.NO_DEM_TIERS,
        interest_rate = EC.ppm(rate),
    )
    loan = MC.LoanCircuitConfig(
        enabled = true,
        mode = mode,
        profit_rate = profit,
        maturity = maturity,
        random_mode = random_mode,
        min_value = min_value,
        max_value = max_value,
        min_maturity = min_maturity,
        max_maturity = max_maturity,
        relative_profit = relative_profit,
        no_loss = no_loss,
    )
    cfg = MC.SimConfig(
        periods = cycles,
        seed = 42,
        record_interval = 1,
        money = money,
        population = MC.PopulationConfig(count = actors),
        wealth = MC.WealthConfig(distribution = MC.WealthDistribution.EQUAL,
                                 equal_amount = EC.money(m0 / actors)),
        transactions = MC.TransactionConfig(enabled = false),
        loan_circuit = loan,
    )
    result = if scenario.kind === :random_g || scenario.kind === :random_lr
        # These paper runs intentionally exceed the scaled-Int64 range; the
        # published treatment is saturation, not a crash.
        EC.set_overflow_mode!(EC.OVERFLOW_SATURATE)
        try
            MC.run_simulation(cfg)
        finally
            EC.set_overflow_mode!(EC.OVERFLOW_ERROR)
        end
    else
        MC.run_simulation(cfg)
    end

    finite = all(isfinite, result.total) &&
             all(isfinite, result.growth_ratio) &&
             all(isfinite, result.loan_debt)
    if scenario.kind === :fixed_g || scenario.kind === :fixed_lr
        debt_pct = result.total[end] == 0.0 ? NaN :
            100.0 * result.loan_debt[end] / result.total[end]
        return Paper1Result(result.periods, debt_pct,
                            result.growth_ratio[end], finite)
    end
    return Paper1Result(result.periods, nothing, nothing, finite)
end

run_paper1(scenario; backend::Symbol = :legacy) =
    backend === :legacy ? _paper1_legacy(scenario) : _paper1_core(scenario)

# ---------------------------------------------------------------------------
# Paper 2 — SUMSY scenarios
# ---------------------------------------------------------------------------

function _paper2_tiers(params)
    return params.demurrage_tiers === nothing ? params.demurrage :
           collect(params.demurrage_tiers)
end

function _paper2_adaptation(name)
    name === :none && return nothing
    name === :one_time_injection && return one_time_money_injection!
    name === :constant_injection && return constant_money_injection!
    name === :one_time_destruction && return one_time_money_destruction!
    name === :constant_destruction && return constant_money_destruction!
    name === :equal_distribution && return equal_money_distribution!
    error("unknown adaptation: $name")
end

function _paper2_legacy_sumsy(params)
    data = run_sumsy_simulation(
        EconoSim.SuMSy(params.gi, params.demurrage_free,
                       _paper2_tiers(params));
        sumsy_interval = params.interval,
        sumsy_transactional = get(params, :transactional, false),
        eligible_actors = params.eligible,
        non_eligible_actors = params.noneligible,
        num_transactions = params.transactions,
        sim_length = params.periods,
        distributed = params.distributed,
        data_handler = money_stock_data_handler(params.interval),
        model_adaptation = _paper2_adaptation(get(params, :adaptation, :none)),
    )[1]
    aggregate = analyse_aggregate(data)
    values = Float64.(aggregate.money_stock)
    return Paper2Result(values[end], maximum(values), minimum(values))
end

function _paper2_core_adaptation(params, tiers, base_wealth)
    name = get(params, :adaptation, :none)
    name === :equal_distribution &&
        return MC.AdaptationConfig(equal_distribution = true,
                                   equal_interval = params.interval)
    name === :one_time_injection &&
        return MC.AdaptationConfig(
            inject_mode = MC.AdaptationMode.PER_ACTOR,
            inject_amount = base_wealth, inject_interval = 1,
            inject_one_time = true)
    name === :constant_injection &&
        return MC.AdaptationConfig(
            inject_mode = MC.AdaptationMode.PER_ACTOR,
            inject_amount = EC.money(params.gi / 2),
            inject_interval = params.interval)
    name === :one_time_destruction &&
        return MC.AdaptationConfig(
            destroy_mode = MC.AdaptationMode.HALF_BALANCE,
            destroy_one_time = true)
    name === :constant_destruction &&
        return MC.AdaptationConfig(
            destroy_mode = MC.AdaptationMode.PER_ACTOR,
            destroy_amount = EC.money(params.gi / 2),
            destroy_interval = params.interval)
    return MC.AdaptationConfig()
end

function _paper2_core_sumsy(params)
    tiers = _paper2_tiers(params)
    demurrage = tiers isa AbstractVector ? EC.make_tiers(tiers) :
                EC.make_tiers(tiers)
    demurrage_free = EC.money(params.demurrage_free)
    base_wealth = EC.telo(EC.money(params.gi), demurrage, demurrage_free)

    n = params.eligible + params.noneligible
    initial = params.noneligible > 0 ?
        EC.Money(round(Int64, Float64(base_wealth.value) * params.eligible / n)) :
        base_wealth
    gi = Vector{UInt8}(undef, n)
    for i in 1:n
        gi[i] = i <= params.eligible ? UInt8(1) : UInt8(0)
    end

    wealth = params.distributed ?
        MC.WealthConfig(distribution = MC.WealthDistribution.EQUAL,
                        equal_amount = initial) :
        MC.WealthConfig(distribution = MC.WealthDistribution.CONCENTRATED,
                        equal_amount = initial)

    periods = Int(params.periods) * Int(params.interval)
    cfg = MC.SimConfig(
        periods = periods,
        seed = 42,
        record_interval = Int(params.interval),
        population = MC.PopulationConfig(count = n, gi_eligible = gi),
        wealth = wealth,
        money = MC.MoneyConfig(
            model = MC.MoneyModel.SUMSY,
            interval = Int(params.interval),
            guaranteed_income = EC.money(params.gi),
            demurrage = demurrage,
            demurrage_free = demurrage_free,
            transactional = get(params, :transactional, false),
        ),
        transactions = MC.TransactionConfig(
            enabled = params.transactions > 0,
            transactions_per_step = Int(params.transactions),
            transfer_rate = 0.2,
        ),
        adaptations = _paper2_core_adaptation(params, demurrage, base_wealth),
        tax = MC.TaxConfig(kind = MC.TaxKind.NONE),
    )
    result = MC.run_simulation(cfg)
    return Paper2Result(result.total[end], maximum(result.total),
                        minimum(result.total))
end

run_paper2_sumsy(scenario; backend::Symbol = :legacy) =
    backend === :legacy ? _paper2_legacy_sumsy(scenario.params) :
                          _paper2_core_sumsy(scenario.params)

function _paper2_legacy_consumer(params, case)
    data = run_consumer_supplier_simulation(
        EconoSim.SuMSy(params.gi, params.demurrage_free,
                       _paper2_tiers(params));
        sumsy_interval = params.interval,
        sim_length = params.periods,
        num_suppliers = 1,
        consumers_per_supplier = case.consumers,
        fulfilled_demand = case.fulfilled_demand,
        net_profit = case.net_profit,
        suppliers_gi_eligible = false,
    )[1]
    typed = analyse_type_data(data)
    return Paper2ConsumerResult(Float64(last(typed.supplier)))
end

function _paper2_core_consumer(params, case)
    tiers = _paper2_tiers(params)
    demurrage = EC.make_tiers(tiers)
    demurrage_free = EC.money(params.demurrage_free)
    initial = EC.telo(EC.money(params.gi), demurrage, demurrage_free)

    n = 1 + Int(case.consumers)
    custom = Vector{EC.Money}(undef, n)
    custom[1] = EC.MONEY_ZERO
    for i in 2:n
        custom[i] = initial
    end
    periods = Int(params.periods) * Int(params.interval)
    cfg = MC.SimConfig(
        periods = periods,
        seed = 42,
        record_interval = periods,
        population = MC.PopulationConfig(count = n),
        wealth = MC.WealthConfig(distribution = MC.WealthDistribution.CUSTOM,
                                 custom = custom),
        money = MC.MoneyConfig(
            model = MC.MoneyModel.SUMSY,
            interval = Int(params.interval),
            guaranteed_income = EC.money(params.gi),
            demurrage = demurrage,
            demurrage_free = demurrage_free,
        ),
        transactions = MC.TransactionConfig(
            enabled = true,
            model = MC.TransactionModel.CONSUMER_SUPPLIER,
            suppliers = 1,
            consumers_per_supplier = Int(case.consumers),
            demand = Int(case.fulfilled_demand),
            price = EC.money(case.net_profit),
        ),
        tax = MC.TaxConfig(kind = MC.TaxKind.NONE),
    )
    state = MC.SimState(n)
    results = MC.ResultBuffers(1)
    MC.run_simulation!(cfg, state, results)
    return Paper2ConsumerResult(EC.currency(state.wealth[1]))
end

run_paper2_consumer(scenario, case; backend::Symbol = :legacy) =
    backend === :legacy ? _paper2_legacy_consumer(scenario.params, case) :
                          _paper2_core_consumer(scenario.params, case)

# ---------------------------------------------------------------------------
# Paper 3 — Belgium inequality
# ---------------------------------------------------------------------------

function _parse_tax_scale(value)
    value === missing && return nothing
    text = String(value)
    matches = collect(eachmatch(r"\[([^\]]+)\]", text))
    isempty(matches) && return nothing
    return parse(Float64, strip(matches[end][1]))
end

function _paper3_legacy(scenario, actors, years; seed = nothing, rng = nothing)
    params = scenario.params
    money_type = params.monetary_type === :sumsy ? M_SUMSY : M_FIXED
    tax_type = params.taxes === :income ? T_INCOME_TAX :
               params.taxes === :demurrage ? T_DEM_TAX :
               params.taxes === :gdp_flat ? T_GDP_FLAT_TAX : T_NO_TAX
    tax_interval = params.tax_interval === :year ? YEAR : MONTH
    population_type = params.population_type === :demographic ?
        P_DEMOGRAPHIC : P_FIXED

    data = simulate_country(
        BE;
        sim_length = years * YEAR,
        data_collection_interval = YEAR,
        num_actors = actors,
        monetary_type = money_type,
        population_type = population_type,
        wealth_distribution = params.wealth_distribution === :equal ?
            W_EQUAL : W_UNEQUAL,
        gdp_growth_per_year = params.gdp_growth_per_year,
        wealth_transfer = params.wealth_transfer,
        wealth_accumulation_advantage = params.zeta,
        gdp_scaling = params.gdp_scaling,
        taxes = tax_type,
        deficit_spending = params.deficit_spending,
        cover_expenses = params.cover_expenses,
        scale_tax_to_target_revenue = params.scale_tax,
        tax_interval = tax_interval,
        vat_active = params.vat,
        deduct_vat_from_taxes = params.deduct_vat,
        vat_interval = MONTH,
        random_seed = seed,
        rng = rng,
    )
    data === nothing && error("legacy country simulation returned nothing")

    analysis = analyse_data(data; income = :income)
    aggregate = analyse_aggregate(data[1])
    model = data[2]

    income_gini = Float64(last(analysis[INCOME_GINI].income_gini))
    income_total = Float64(last(analysis[I_PERCENTAGE].TOP_10))
    return Paper3Result(
        Float64(last(analysis[WEALTH_GINI].wealth_gini)),
        income_gini,
        Float64(last(aggregate.money_stock)),
        Float64(last(model.debt)),
        Float64(last(model.collected_tax)),
        _parse_tax_scale(last(model.tax_scale)),
        Float64(last(analysis[W_PERCENTAGE].TOP_10)),
        Float64(last(analysis[W_PERCENTAGE].BOTTOM_50)),
        income_total,
        Float64(last(analysis[I_PERCENTAGE].BOTTOM_50)),
    )
end

function _paper3_core_config(scenario, actors, years; seed = 42)
    params = scenario.params
    country = MC.belgium()
    population = MC.population_total(country)
    per_capita = MC.money_per_capita(country)
    gdp_per_capita = MC.gdp_per_capita(country)

    wealth = params.wealth_distribution === :equal ?
        MC.WealthConfig(distribution = MC.WealthDistribution.EQUAL,
                        equal_amount = per_capita) :
        MC.WealthConfig(distribution = MC.WealthDistribution.CUSTOM,
                        custom = MC.unequal_wealth(country, actors))

    money = if params.monetary_type === :sumsy
        # Legacy divides two Currency values, so the country demurrage rate is
        # rounded to four decimals before `make_tiers`.
        rate = round(Float64(country.sumsy.flat_gi.value) /
                     Float64(per_capita.value), digits = 4)
        MC.MoneyConfig(model = MC.MoneyModel.SUMSY,
                       interval = country.sumsy.interval,
                       guaranteed_income = country.sumsy.flat_gi,
                       demurrage = EC.make_tiers(rate),
                       demurrage_free = country.sumsy.demurrage_free)
    else
        MC.MoneyConfig(model = MC.MoneyModel.FIXED, interval = 1)
    end

    tax_interval = params.tax_interval === :year ? 12 : 1
    net_expenses = div((country.government.expenses -
                        country.government.interest_cost) * tax_interval,
                       population)
    income_target = div(country.government.income * tax_interval, population)
    target = params.cover_expenses ? net_expenses : income_target

    tax = if params.taxes === :income
        brackets = vcat(country.government.tax_brackets, [typemax(EC.Money)])
        MC.TaxConfig(
            kind = MC.TaxKind.INCOME,
            interval = tax_interval,
            brackets = brackets,
            bracket_rates = copy(country.government.tax_rates),
            target_revenue = target * actors,
            scale_to_target = params.scale_tax,
            notional = MC.unequal_income(country, actors; period = tax_interval),
            allow_negative = true,
        )
    elseif params.taxes === :demurrage
        rate = Float64(net_expenses.value) / Float64(per_capita.value)
        MC.TaxConfig(
            kind = MC.TaxKind.DEMURRAGE,
            interval = tax_interval,
            brackets = [typemax(EC.Money)],
            bracket_rates = [EC.ppm(rate)],
            target_revenue = target * actors,
            scale_to_target = params.scale_tax,
            allow_negative = true,
        )
    elseif params.taxes === :gdp_flat
        rate = Float64(country.government.income.value) /
               Float64(country.government.gdp.value)
        MC.TaxConfig(
            kind = MC.TaxKind.INCOME,
            interval = MONTH,
            brackets = [typemax(EC.Money)],
            bracket_rates = [EC.ppm(rate)],
            scale_to_target = false,
            notional = MC.unequal_income(country, actors; period = MONTH),
            allow_negative = true,
        )
    else
        MC.TaxConfig(kind = MC.TaxKind.NONE)
    end

    vat_rate = Float64(country.government.vat_income.value) /
               Float64(country.government.gdp.value)
    vat = MC.VatConfig(
        enabled = params.vat,
        rate = vat_rate,
        interval = MONTH,
        deduct_from_taxes = params.deduct_vat,
        recipient = MC.TaxRecipient.EVERYONE,
    )

    monthly_net_expenses = div(country.government.expenses -
                               country.government.interest_cost, population)
    expenses = (params.cover_expenses || params.deficit_spending) ?
        monthly_net_expenses * actors : EC.MONEY_ZERO
    government = MC.GovernmentConfig(
        enabled = true,
        expenses = expenses,
        deficit_spending = params.deficit_spending,
        initial_debt = div(country.government.debt * actors, population),
    )

    gdp = MC.GdpConfig(
        enabled = true,
        per_capita = EC.Money(round(Int64,
            Float64(gdp_per_capita.value) * params.gdp_scaling)),
        growth_ppm = EC.ppm(params.gdp_growth_per_year),
        interval = 1,
    )

    return MC.SimConfig(
        periods = years * MONTH * 12,
        seed = seed,
        record_interval = 12,
        money = money,
        wealth = wealth,
        transactions = MC.TransactionConfig(
            enabled = false,
            transfer_rate = params.wealth_transfer,
            wealth_advantage = params.zeta,
            allow_negative = true,
        ),
        tax = tax,
        population = MC.PopulationConfig(count = actors),
        government = government,
        gdp = gdp,
        vat = vat,
    )
end

function _paper3_core(scenario, actors, years; seed = 42)
    cfg = _paper3_core_config(scenario, actors, years; seed = seed)
    result = MC.run_simulation(cfg)
    index = result.periods
    shares_base = (index - 1) * 6
    bottom50 = 100.0 * result.shares[shares_base + 3]
    bottom90 = 100.0 * result.shares[shares_base + 4]
    has_income = result.income_gini[index] >= 0.0
    income_bottom50 = has_income ?
        100.0 * result.income_shares[shares_base + 3] : NaN
    income_bottom90 = has_income ?
        100.0 * result.income_shares[shares_base + 4] : NaN
    has_tax = scenario.params.taxes !== :none
    return Paper3Result(
        result.gini[index],
        result.income_gini[index],
        result.total[index],
        result.government_debt[index],
        result.tax_collected[index],
        has_tax ? result.tax_scale[index] : nothing,
        100.0 - bottom90,
        bottom50,
        100.0 - income_bottom90,
        income_bottom50,
    )
end

run_paper3(scenario; backend::Symbol = :legacy,
           actors::Integer = baseline_paper3_actors(),
           years::Integer = baseline_paper3_years(),
           seed::Union{Nothing, Integer} = nothing) =
    backend === :legacy ?
        _paper3_legacy(scenario, Int(actors), Int(years); seed = seed) :
        _paper3_core(scenario, Int(actors), Int(years);
                     seed = seed === nothing ? 42 : Int(seed))

export Paper1Result, Paper2Result, Paper2ConsumerResult, Paper3Result
export run_paper1, run_paper2_sumsy, run_paper2_consumer, run_paper3
export baseline_paper3_actors, baseline_paper3_years
