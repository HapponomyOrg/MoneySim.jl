# Multi-seed paper-3 comparison.
#
# The legacy and core backends use different PRNGs (Julia's global
# MersenneTwister vs the explicit xorshift64 in EconoSimCore), and paper-3
# fixed-money scenarios are chaotic. A single seed can therefore show a
# distribution delta that is mostly RNG noise. This suite runs both backends
# across `PAPER_SEEDS` seeds and compares the *mean* outcome, with a tighter
# tolerance than the single-seed baseline check.
#
# Enable with:
#   PAPER_SEEDS=5 PAPER_TESTS=fast julia --project=. test/papers/run.jl
# or run only this suite:
#   PAPER_TESTS=seeds julia --project=. test/papers/run.jl

using Statistics
using Printf

const PAPER_SEED_COUNT = begin
    count = parse(Int, get(ENV, "PAPER_SEEDS", "5"))
    count >= 2 || error("PAPER_SEEDS must be at least 2")
    count
end

function _seed_stats(results, field)
    values = Float64[]
    for result in results
        value = getfield(result, field)
        value === nothing && return nothing
        value = Float64(value)
        isnan(value) && return nothing
        push!(values, value)
    end
    isempty(values) && return nothing
    return (mean(values), std(values))
end

function _seed_tolerances(scenario)
    if scenario.params.monetary_type === :sumsy
        return (gini = 0.03, scale = 0.20, share = 3.5,
                money = 0.01, debt = 0.01, tax = 0.015)
    end
    return (gini = 0.05, scale = 0.25, share = 4.0,
            money = 0.01, debt = 0.01, tax = 0.015)
end

@testset "Paper 3 — seed robustness" begin
    @info "Paper-3 seed sweep" seeds = PAPER_SEED_COUNT
    gini_means = Dict{Symbol,Float64}()

    for scenario in PAPER3_SCENARIOS
        tolerance = _seed_tolerances(scenario)
        seeds = 1:PAPER_SEED_COUNT
        legacy = [run_paper3(scenario; backend = :legacy, seed = seed)
                  for seed in seeds]
        core = [run_paper3(scenario; backend = :core, seed = seed)
                for seed in seeds]

        @testset "$(scenario.name)" begin
            for (field, tolerance_value, relative) in (
                (:gini_wealth, tolerance.gini, false),
                (:gini_income, tolerance.gini, false),
                (:top10_share, tolerance.share, false),
                (:bottom50_share, tolerance.share, false),
                (:income_top10_share, tolerance.share, false),
                (:income_bottom50_share, tolerance.share, false),
                (:tax_scale, tolerance.scale, false),
                (:money_stock, tolerance.money, true),
                (:public_debt, tolerance.debt, true),
                (:tax_collected, tolerance.tax, true),
            )
                legacy_stats = _seed_stats(legacy, field)
                core_stats = _seed_stats(core, field)
                (legacy_stats === nothing || core_stats === nothing) && continue
                legacy_mean, _ = legacy_stats
                core_mean, _ = core_stats
                if relative
                    @test isapprox(core_mean, legacy_mean; rtol = tolerance_value)
                else
                    @test isapprox(core_mean, legacy_mean; atol = tolerance_value)
                end
            end
        end

        legacy_gini = _seed_stats(legacy, :gini_wealth)
        core_gini = _seed_stats(core, :gini_wealth)
        if legacy_gini !== nothing && core_gini !== nothing
            gini_means[scenario.name] = core_gini[1]
            @printf("  %-4s giniW legacy %.4f±%.4f core %.4f±%.4f Δ %+.4f\n",
                    String(scenario.name), legacy_gini[1], legacy_gini[2],
                    core_gini[1], core_gini[2],
                    core_gini[1] - legacy_gini[1])
        end
    end

    if haskey(gini_means, :a1)
        @test gini_means[:a2] < gini_means[:a1]
        haskey(gini_means, :a3) && @test gini_means[:a3] < gini_means[:a1]
        haskey(gini_means, :b1) && @test gini_means[:b1] > gini_means[:a1]
    end
end
