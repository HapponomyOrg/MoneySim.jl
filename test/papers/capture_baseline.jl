# Capture the pre-refactor (legacy MoneySim) numbers for every scenario.
#
# Usage:
#   PAPER_TESTS=write julia --project=. test/papers/run.jl
#
# The paper-3 legacy country runs are captured at a reduced scale by default
# (1,000 actors × 10 years) so the live baseline stays practical. Override with
# `PAPER3_BASELINE_ACTORS` and `PAPER3_BASELINE_YEARS` (for example 10000 and
# 100 for a paper-scale nightly capture).

using TOML
using Dates

function _paper1_record(result::Paper1Result)
    record = Dict{String,Any}(
        "length" => result.length,
        "finite" => result.finite,
    )
    result.debt_ratio_pct !== nothing &&
        (record["debt_ratio_pct"] = result.debt_ratio_pct)
    result.growth_ratio_pct !== nothing &&
        (record["growth_ratio_pct"] = result.growth_ratio_pct)
    return record
end

function _paper2_record(result::Paper2Result)
    return Dict{String,Any}(
        "money_stock" => result.money_stock,
        "max_money_stock" => result.max_money_stock,
        "min_money_stock" => result.min_money_stock,
    )
end

function _paper3_record(result::Paper3Result)
    record = Dict{String,Any}(
        "gini_wealth" => result.gini_wealth,
        "gini_income" => result.gini_income,
        "money_stock" => result.money_stock,
        "public_debt" => result.public_debt,
        "tax_collected" => result.tax_collected,
        "top10_share" => result.top10_share,
        "bottom50_share" => result.bottom50_share,
        "income_top10_share" => result.income_top10_share,
        "income_bottom50_share" => result.income_bottom50_share,
    )
    result.tax_scale !== nothing &&
        (record["tax_scale"] = result.tax_scale)
    return record
end

function _git_sha()
    try
        return readchomp(`git -C $(joinpath(@__DIR__, "..", "..")) rev-parse HEAD`)
    catch
        return "unknown"
    end
end

function capture_baseline()
    actors = baseline_paper3_actors()
    years = baseline_paper3_years()

    baseline = Dict{String,Any}(
        "meta" => Dict{String,Any}(
            "format" => 1,
            "captured_at" => string(Dates.now()),
            "julia_version" => string(VERSION),
            "money_sim_sha" => _git_sha(),
            "paper3_actors" => actors,
            "paper3_years" => years,
        ),
    )

    @info "Capturing paper-1 legacy baseline"
    paper1 = Dict{String,Any}()
    for scenario in PAPER1_SCENARIOS
        paper1[String(scenario.name)] =
            _paper1_record(run_paper1(scenario; backend = :legacy))
    end
    baseline["paper1"] = paper1

    @info "Capturing paper-2 legacy baseline"
    paper2 = Dict{String,Any}()
    for scenario in PAPER2_SCENARIOS
        @info "paper 2 legacy" scenario = scenario.name
        paper2[String(scenario.name)] =
            _paper2_record(run_paper2_sumsy(scenario; backend = :legacy))
    end
    baseline["paper2"] = paper2

    @info "Capturing paper-2 consumer–supplier legacy baseline"
    consumer = Dict{String,Any}()
    for scenario in PAPER2_CONSUMER_SUPPLIER
        cases = Dict{String,Any}()
        for (index, case) in enumerate(scenario.cases)
            result = run_paper2_consumer(scenario, case; backend = :legacy)
            cases["case$(index)"] = Dict{String,Any}(
                "supplier_balance" => result.supplier_balance)
        end
        consumer[String(scenario.name)] = cases
    end
    baseline["paper2_consumer_supplier"] = consumer

    @info "Capturing paper-3 legacy baseline" actors = actors years = years
    paper3 = Dict{String,Any}()
    for scenario in PAPER3_SCENARIOS
        @info "paper 3 legacy" scenario = scenario.name
        paper3[String(scenario.name)] =
            _paper3_record(run_paper3(scenario; backend = :legacy))
    end
    baseline["paper3"] = paper3

    mkpath(PAPER_FIXTURES_DIR)
    open(PAPER_BASELINE_PATH, "w") do io
        TOML.print(io, baseline; sorted = true)
    end
    @info "Wrote baseline" path = PAPER_BASELINE_PATH
    return baseline
end
