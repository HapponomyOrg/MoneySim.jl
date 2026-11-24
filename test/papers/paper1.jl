# Paper 1 — Post-Keynesian endogenous money.
#
# Exact assertions taken from the notebook output:
#   jupyter/paper 1/Computational Analysis of the Properties of
#   Post-Keynesian Endogenous Money Systems.ipynb
#
# `scenarios.jl` must be included before this file.

using Test
using MoneySim

last_pct(x) = round(Float64(last(x)), digits = 2)

# The notebooks were produced with an older Julia/FixedPointDecimals; the two
# collapse cases differ in the second decimal. Keep a small tolerance for the
# ratios while still catching meaningful drift.
same_pct(actual, expected) = isapprox(actual, expected; atol = 0.1, rtol = 1e-4)

@testset "Paper 1 — post-Keynesian endogenous money" begin
    for scenario in PAPER1_SCENARIOS
        @testset "$(scenario.name)" begin
            expected = scenario.expected
            params = scenario.params

            if scenario.kind === :fixed_g
                data = simulate_fixed_g(; params...)

                if :debt_ratio_pct in keys(expected)
                    @test same_pct(last_pct(debt_ratio(data)), expected.debt_ratio_pct)
                end
                if :baseline_debt_ratio_pct in keys(expected)
                    @test same_pct(last_pct(debt_ratio(data)), expected.baseline_debt_ratio_pct)
                end
                if :growth_ratio_pct in keys(expected)
                    @test same_pct(last_pct(growth_ratio(data)), expected.growth_ratio_pct)
                end
                if :length in keys(expected)
                    @test length(data) == expected.length
                end

            elseif scenario.kind === :fixed_lr
                data = simulate_fixed_LR(; params...)

                if :length in keys(expected)
                    @test length(data) == expected.length
                end
                if :debt_ratio_pct in keys(expected)
                    @test same_pct(last_pct(debt_ratio(data)), expected.debt_ratio_pct)
                end
                if :baseline_debt_ratio_pct in keys(expected)
                    @test same_pct(last_pct(debt_ratio(data)), expected.baseline_debt_ratio_pct)
                end
                if :growth_ratio_pct in keys(expected)
                    @test same_pct(last_pct(growth_ratio(data)), expected.growth_ratio_pct)
                end

            elseif scenario.kind === :random_g
                data = simulate_random_g(; params...)

                if :length in keys(expected)
                    @test length(data) == expected.length
                end
                if :finite in keys(expected) && expected.finite
                    @test all(x -> isfinite(Float64(x)), debt_ratio(data))
                    @test all(x -> isfinite(Float64(x)), growth_ratio(data))
                end
            else
                @test false
            end
        end
    end

    @testset "phase-boundary sweep" begin
        # p relative to g: below, equal, above. Every trajectory must stay
        # finite; the economic interpretation is checked by the named cases.
        for p in (0.0, 0.008, 0.01, 0.05, 0.10)
            data = simulate_fixed_g(g = 0.05, p = p, m = 20, cycles = 100)
            @test all(x -> isfinite(Float64(x)), debt_ratio(data))
            @test all(x -> isfinite(Float64(x)), growth_ratio(data))
        end
    end
end
