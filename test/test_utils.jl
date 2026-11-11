using Test
using EconoSim
using MoneySim
using Agents

# The calculate_taxes testsets were dropped on 2026-11-11: calculate_taxes is commented out in src/utils.jl
# and is not brought back. The tests below cover what utils.jl defines.

@testset "remove_index!" begin
    v = [1, 2, 3, 4]
    @test remove_index!(v, 2) == [1, 3, 4]
    @test v == [1, 2, 3, 4] # the input is not changed
end

@testset "calculate_percentile_ranges" begin
    ranges = calculate_percentile_ranges(1000)
    @test ranges[Int(BOTTOM_0_1) + 1] == 1:1
    @test ranges[Int(BOTTOM_1) + 1] == 1:10
    @test ranges[Int(BOTTOM_10) + 1] == 1:100
    @test ranges[Int(BOTTOM_50) + 1] == 1:500
    @test ranges[Int(LOW_MIDDLE_40) + 1] == 101:500
    @test ranges[Int(HIGH_MIDDLE_40) + 1] == 501:900
    @test ranges[Int(TOP_10) + 1] == 901:1000
    @test ranges[Int(TOP_1) + 1] == 991:1000
    @test ranges[Int(TOP_0_1) + 1] == 1000:1000

    # Small populations still give non-empty ranges.
    for range in calculate_percentile_ranges(10)
        @test !isempty(range)
    end
end

@testset "is_broke and one_non_broke" begin
    model = create_econo_model(MonetaryActor{Currency, Balance{Currency}})
    abmproperties(model)[:broke_threshold] = 10

    # create_monetary_actor! takes the model's next id; add each actor before creating the next one.
    poor = add_actor!(model, create_monetary_actor!(model))
    rich = add_actor!(model, create_monetary_actor!(model))
    book_asset!(get_balance(poor), SUMSY_DEP, 5)
    book_asset!(get_balance(rich), SUMSY_DEP, 50)

    @test is_broke(model, poor)
    @test !is_broke(model, rich)
    @test one_non_broke(model)

    book_asset!(get_balance(poor), SUMSY_DEP, 10)
    @test !one_non_broke(model)
end
