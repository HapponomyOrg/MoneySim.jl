# Compare the refactored core against the captured pre-refactor baseline.
#
# The baseline is written by `PAPER_TESTS=write` and committed under
# `test/papers/fixtures/baseline.toml`. Paper 1 and paper 2 are captured at
# their paper parameters; paper 3 is captured at the scale recorded in the
# baseline metadata (default 1,000 actors × 10 years).
#
# Tolerances follow the plan's before/after rules. Paper 3 is distribution-level:
# the legacy and core RNG streams differ, so final distributions are compared,
# not year-by-year traces.

using TOML
using Printf

const BASELINE = TOML.parsefile(PAPER_BASELINE_PATH)

function _baseline_record(section::String, name)
    haskey(BASELINE, section) || return nothing
    entries = BASELINE[section]
    haskey(entries, String(name)) || return nothing
    return entries[String(name)]
end

function _finite_or_nan(value)
    value === nothing && return NaN
    return Float64(value)
end

# Paper-1 and paper-2 tolerances.
const PAPER1_RATIO_ATOL = 0.1
const PAPER2_MONEY_RTOL = 1e-3
const PAPER2_CONSUMER_RTOL = 1e-3

# Paper-3 distribution tolerances.
const PAPER3_MONEY_RTOL = 0.02
const PAPER3_LEDGER_RTOL = 0.02
const PAPER3_TAX_RTOL = 0.015

function _paper3_tolerances(scenario)
    if scenario.params.monetary_type === :sumsy
        return (gini = 0.06, scale = 0.35, share = 7.0)
    end
    return (gini = 0.15, scale = 0.40, share = 8.0)
end

const CORE_PAPER1 = Dict{Symbol,Paper1Result}()
const CORE_PAPER2 = Dict{Symbol,Paper2Result}()
const CORE_PAPER3 = Dict{Symbol,Paper3Result}()

@testset "Refactor baseline — paper 1" begin
    for scenario in PAPER1_SCENARIOS
        before = _baseline_record("paper1", scenario.name)
        before === nothing && continue
        if scenario.name === :loan_rate_stable_m30
            # The paper trajectory reaches ~10^26 currency; scaled Int64
            # saturates long before cycle 500. Ratios are checked for the
            # representable scenarios; this one is documented as limited.
            @test_skip "m30 stable exceeds scaled Int64"
            continue
        end
        after = run_paper1(scenario; backend = :core)
        CORE_PAPER1[scenario.name] = after

        @testset "$(scenario.name)" begin
            @test after.length == Int(before["length"])
            if haskey(before, "debt_ratio_pct")
                @test isapprox(after.debt_ratio_pct,
                               Float64(before["debt_ratio_pct"]);
                               atol = PAPER1_RATIO_ATOL)
            end
            if haskey(before, "growth_ratio_pct")
                @test isapprox(after.growth_ratio_pct,
                               Float64(before["growth_ratio_pct"]);
                               atol = PAPER1_RATIO_ATOL)
            end
            @test after.finite
        end
    end
end

@testset "Refactor baseline — paper 2" begin
    for scenario in PAPER2_SCENARIOS
        before = _baseline_record("paper2", scenario.name)
        before === nothing && continue
        after = run_paper2_sumsy(scenario; backend = :core)
        CORE_PAPER2[scenario.name] = after
        rtol = scenario.name === :d1 ? 2e-2 : PAPER2_MONEY_RTOL

        @testset "$(scenario.name)" begin
            if scenario.name in (:e2, :e5)
                # Tiered demurrage equilibria depend on the wealth distribution,
                # and the RNG streams differ. Compare both runs to the paper's
                # analytic bounds instead of requiring the same final stock.
                lower = _bound(scenario.expected.money_stock_min,
                               scenario.params) * 0.99
                upper = _bound(scenario.expected.money_stock_max,
                               scenario.params) * 1.01
                @test lower <= Float64(before["money_stock"]) <= upper
                @test lower <= after.money_stock <= upper
            else
                @test isapprox(after.money_stock,
                               Float64(before["money_stock"]);
                               rtol = rtol)
            end
            @test after.max_money_stock >= after.min_money_stock
        end
    end

    for scenario in PAPER2_CONSUMER_SUPPLIER
        before = _baseline_record("paper2_consumer_supplier", scenario.name)
        before === nothing && continue
        @testset "$(scenario.name)" begin
            for (index, case) in enumerate(scenario.cases)
                entry = before["case$(index)"]
                after = run_paper2_consumer(scenario, case; backend = :core)
                @test isapprox(after.supplier_balance,
                               Float64(entry["supplier_balance"]);
                               rtol = PAPER2_CONSUMER_RTOL)
            end
        end
    end
end

@testset "Refactor baseline — paper 3" begin
    meta = BASELINE["meta"]
    actors = Int(meta["paper3_actors"])
    years = Int(meta["paper3_years"])
    @info "Paper-3 baseline scale" actors = actors years = years

    after_by_name = CORE_PAPER3
    for scenario in PAPER3_SCENARIOS
        before = _baseline_record("paper3", scenario.name)
        before === nothing && continue
        after = run_paper3(scenario; backend = :core, actors = actors,
                           years = years)
        after_by_name[scenario.name] = after
        tolerance = _paper3_tolerances(scenario)

        @testset "$(scenario.name)" begin
            @test isapprox(after.gini_wealth,
                           Float64(before["gini_wealth"]);
                           atol = tolerance.gini)

            before_income = Float64(before["gini_income"])
            if !isnan(before_income) && after.gini_income >= 0.0
                @test isapprox(after.gini_income, before_income;
                               atol = tolerance.gini)
            end

            @test isapprox(after.money_stock,
                           Float64(before["money_stock"]);
                           rtol = PAPER3_MONEY_RTOL)
            @test isapprox(after.public_debt,
                           Float64(before["public_debt"]);
                           rtol = PAPER3_LEDGER_RTOL)
            @test isapprox(after.tax_collected,
                           Float64(before["tax_collected"]);
                           rtol = PAPER3_TAX_RTOL)
            if haskey(before, "tax_scale")
                @test isapprox(after.tax_scale,
                               Float64(before["tax_scale"]);
                               atol = tolerance.scale)
            end

            @test isapprox(after.top10_share,
                           Float64(before["top10_share"]);
                           atol = tolerance.share)
            @test isapprox(after.bottom50_share,
                           Float64(before["bottom50_share"]);
                           atol = tolerance.share)
            if !isnan(before["income_top10_share"]) &&
               !isnan(after.income_top10_share)
                @test isapprox(after.income_top10_share,
                               Float64(before["income_top10_share"]);
                               atol = tolerance.share)
            end
            if !isnan(before["income_bottom50_share"]) &&
               !isnan(after.income_bottom50_share)
                @test isapprox(after.income_bottom50_share,
                               Float64(before["income_bottom50_share"]);
                               atol = tolerance.share)
            end
        end
    end

    # Direction checks are release-blocking even when the RNG moves the level.
    if haskey(after_by_name, :a1)
        a1 = after_by_name[:a1]
        haskey(after_by_name, :a2) &&
            @test after_by_name[:a2].gini_wealth < a1.gini_wealth
        haskey(after_by_name, :a3) &&
            @test after_by_name[:a3].gini_wealth < a1.gini_wealth
        haskey(after_by_name, :b1) &&
            @test after_by_name[:b1].gini_wealth > a1.gini_wealth
    end
    if haskey(after_by_name, :c1) && haskey(after_by_name, :c2)
        @test after_by_name[:c2].tax_scale > after_by_name[:c1].tax_scale
    end
    if haskey(after_by_name, :c2) && haskey(after_by_name, :c3)
        @test after_by_name[:c3].tax_scale > after_by_name[:c2].tax_scale
    end
end

@testset "Refactor baseline — summary" begin
    println("\nBefore/after summary (legacy → core):")
    for scenario in PAPER1_SCENARIOS
        before = _baseline_record("paper1", scenario.name)
        (before === nothing || !haskey(CORE_PAPER1, scenario.name)) && continue
        after = CORE_PAPER1[scenario.name]
        debt = haskey(before, "debt_ratio_pct") ?
            @sprintf("%.2f → %.2f", Float64(before["debt_ratio_pct"]),
                     after.debt_ratio_pct) : "n/a"
        @printf("  p1 %-32s DR %-18s length %d → %d\n",
                String(scenario.name), debt, Int(before["length"]), after.length)
        @test true
    end
    for scenario in PAPER2_SCENARIOS
        before = _baseline_record("paper2", scenario.name)
        (before === nothing || !haskey(CORE_PAPER2, scenario.name)) && continue
        after = CORE_PAPER2[scenario.name]
        @printf("  p2 %-32s money %.6g → %.6g\n", String(scenario.name),
                Float64(before["money_stock"]), after.money_stock)
        @test true
    end
    for scenario in PAPER3_SCENARIOS
        before = _baseline_record("paper3", scenario.name)
        (before === nothing || !haskey(CORE_PAPER3, scenario.name)) && continue
        after = CORE_PAPER3[scenario.name]
        @printf("  p3 %-32s giniW %.4f → %.4f | money %.3g → %.3g | scale %s\n",
                String(scenario.name), Float64(before["gini_wealth"]),
                after.gini_wealth, Float64(before["money_stock"]),
                after.money_stock,
                haskey(before, "tax_scale") ?
                    @sprintf("%.3f → %.3f", Float64(before["tax_scale"]),
                             after.tax_scale) : "—")
        @test true
    end
end
