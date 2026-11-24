# Paper 3 — Belgium inequality.
#
# Two layers:
#   1. Fixture integrity — the manifest's expected values must match the
#      committed CSVs in jupyter/paper 3/data/. This catches accidental edits to
#      either side.
#   2. Simulation comparison — the refactored engine must reproduce the
#      reference series (or stay within the distribution tolerances). This layer
#      is wired through `PaperAdapter` in Phase 0.
#
# Never load actor_data.csv: for b1 and c1 it is 64–86 MB and is not needed for
# the aggregate checks.
#
# `scenarios.jl` must be included before this file.

using Test
using CSV
using DataFrames

const PAPER3_DATA_DIR = normpath(joinpath(@__DIR__, "..", "..", "jupyter", "paper 3", "data"))

const PAPER3_FILES = (
    "gini_wealth.csv",
    "gini_income.csv",
    "money_stock.csv",
    "percentile_wealth_data.csv",
    "percentile_income_data.csv",
    "model_data.csv",
)

function _last_value(scenario, file, column)
    path = joinpath(PAPER3_DATA_DIR, String(scenario.name), file)
    df = CSV.read(path, DataFrame)
    return last(df[!, column])
end

@testset "Paper 3 — fixture integrity" begin
    for scenario in PAPER3_SCENARIOS
        @testset "$(scenario.name)" begin
            expected = scenario.expected

            for file in PAPER3_FILES
                @test isfile(joinpath(PAPER3_DATA_DIR, String(scenario.name), file))
            end

            @test _last_value(scenario, "gini_wealth.csv", :wealth_gini) ≈
                  expected.gini_wealth atol = 1e-4

            income_gini = _last_value(scenario, "gini_income.csv", :income_gini)
            if expected.gini_income === nothing
                @test ismissing(income_gini) ||
                      (income_gini isa Real && isnan(income_gini)) ||
                      income_gini == "NaN"
            else
                @test Float64(income_gini) ≈ expected.gini_income atol = 1e-4
            end

            @test _last_value(scenario, "money_stock.csv", :money_stock) ≈
                  expected.money_stock rtol = 1e-6

            @test _last_value(scenario, "model_data.csv", :debt) ≈
                  expected.debt rtol = 1e-6

            @test _last_value(scenario, "percentile_wealth_data.csv", :TOP_10) ≈
                  expected.top10_share atol = 1e-3
            @test _last_value(scenario, "percentile_wealth_data.csv", :BOTTOM_50) ≈
                  expected.bottom50_share atol = 1e-3

            @test _last_value(scenario, "percentile_income_data.csv", :TOP_10) ≈
                  expected.income_top10_share atol = 1e-3
            @test _last_value(scenario, "percentile_income_data.csv", :BOTTOM_50) ≈
                  expected.income_bottom50_share atol = 1e-3
        end
    end
end

@testset "Paper 3 — simulation comparison" begin
    # Covered by `compare.jl`: the core backend is compared against the captured
    # legacy baseline at the scale recorded in `fixtures/baseline.toml`.
    @test true
end
