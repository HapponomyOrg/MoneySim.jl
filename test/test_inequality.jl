using EconoSim
using MoneySim
using Test

@testset "InequalityData" begin
    inequality_data = InequalityData(1000000,   # Top 0.1%
                                        100000, # Top 1%
                                        10000,  # Top 10%
                                        1000,   # High middle 40%
                                        100,    # Low middle 40%
                                        10,     # Bottom 10%
                                        1,      # Bottom 1%
                                        0)      # Bottom 0.1%

    @test inequality_data.top_0_1 == 1000000
    @test inequality_data.top_1 == 100000
    @test inequality_data.top_10 == 10000
    @test inequality_data.high_middle_40 == 1000
    @test inequality_data.low_middle_40 == 100
    @test inequality_data.bottom_10 == 10
    @test inequality_data.bottom_1 == 1
    @test inequality_data.bottom_0_1 == 0

    inequality_data = InequalityData(4000000,   # Top 0.1%
                                        400000, # Top 1%
                                        40000,  # Top 10%
                                        4000,   # High middle 40%
                                        400,    # Low middle 40%
                                        40,     # Bottom 10%
                                        4,      # Bottom 1%
                                        0,      # Bottom 0.1%
                                        money_per_head = 5764)

    @test (inequality_data.top_10 * 0.1
            + inequality_data.high_middle_40 * 0.4
            + inequality_data.low_middle_40 * 0.4
            + inequality_data.bottom_10 * 0.1) == 5764
end

@testset "Update for overlap" begin
    s_0_1 = 100000
    s_1 = 19000
    s_10 = 2800
    t_0_1, t_1, t_10 = MoneySim.adjust_for_overlap(s_0_1, s_1, s_10)
    @test round(100 * s_10) == round(t_0_1 + 9 * t_1 + 90 * t_10)

    s_0_1 = nothing
    s_1 = 10000
    s_10 = 1900
    t_0_1, t_1, t_10 = MoneySim.adjust_for_overlap(s_0_1, s_1, s_10)
    @test round(100 * s_10) == round(t_0_1 + 9 * t_1 + 90 * t_10)

    s_0_1 = 50000
    s_1 = nothing
    s_10 = 1000
    t_0_1, t_1, t_10 = MoneySim.adjust_for_overlap(s_0_1, s_1, s_10)
    @test round(100 * s_10) == round(t_0_1 + 9 * t_1 + 90 * t_10)

    s_0_1 = nothing
    s_1 = nothing
    s_10 = 10000
    t_0_1, t_1, t_10 = MoneySim.adjust_for_overlap(s_0_1, s_1, s_10)
    @test round(100 * s_10) == round(t_0_1 + 9 * t_1 + 90 * t_10)

    s_0_1 = -100000
    s_1 = -10000
    s_10 = 1000
    t_0_1, t_1, t_10 = MoneySim.adjust_for_overlap(s_0_1, s_1, s_10)
    @test round(100 * s_10) == round(t_0_1 + 9 * t_1 + 90 * t_10)

    s_0_1 = -100000
    s_1 = nothing
    s_10 = 1000
    t_0_1, t_1, t_10 = MoneySim.adjust_for_overlap(s_0_1, s_1, s_10)
    @test round(100 * s_10) == round(t_0_1 + 9 * t_1 + 90 * t_10)
end

@testset "Update InequalityData for overlap" begin
    inequality_data = InequalityData(4000000,   # Top 0.1%
                                        400000, # Top 1%
                                        40000,  # Top 10%
                                        4000,   # High middle 40%
                                        400,    # Low middle 40%
                                        40,     # Bottom 10%
                                        4,      # Bottom 1%
                                        0,      # Bottom 0.1%
                                        money_per_head = 5764)

top_0_1, top_1, top_10 = MoneySim.adjust_for_overlap(inequality_data.top_0_1,
                                                    inequality_data.top_1,
                                                    inequality_data.top_10)
bottom_0_1, bottom_1, bottom_10 = MoneySim.adjust_for_overlap(inequality_data.bottom_0_1,
                                                                inequality_data.bottom_1,
                                                                inequality_data.bottom_10)

@test round((top_0_1
            + top_1 * 9
            + top_10 * 90
            + inequality_data.high_middle_40 * 400
            + inequality_data.low_middle_40 * 400
            + bottom_10 * 90
            + bottom_1 * 9
            + bottom_0_1) / 1000) == 5764
end

@testset "Update InequalityData for overlap - Data Belgium" begin
M2 = Currency(639000000000)
POP_MIN_18 = 1314555 + 274738 + 747040
POP_18_TO_64 = 4029828 + 804889 + 2215697
POP_65_PLUS = 1430423 + 161548 + 718838
POPULATION = POP_MIN_18 + POP_18_TO_64 + POP_65_PLUS
M2_PER_CAPITA = M2 / POPULATION
inequality_data = InequalityData(9347930,     # Top 0.1%
                                3988639.8,    # Top 1%
                                1388465.6,    # Top 10%
                                266649.9,     # High middle 40%
                                51125.0871,   # Low middle 40%
                                -709.6,       # Bottom 10%
                                -44162.4,     # Bottom 1%
                                nothing,      # Bottom 0.1% - data not available
                                money_per_head = M2_PER_CAPITA)

top_0_1, top_1, top_10 = MoneySim.adjust_for_overlap(inequality_data.top_0_1,
                                                    inequality_data.top_1,
                                                    inequality_data.top_10)
@test round(100 * inequality_data.top_10) == round(top_0_1 + 9 * top_1 + 90 * top_10)

bottom_0_1, bottom_1, bottom_10 = MoneySim.adjust_for_overlap(inequality_data.bottom_0_1,
                                                            inequality_data.bottom_1,
                                                            inequality_data.bottom_10)
@test round(100 * inequality_data.bottom_10) == round(bottom_0_1 + 9 * bottom_1 + 90 * bottom_10)

@test round((top_0_1
        + top_1 * 9
        + top_10 * 90
        + inequality_data.high_middle_40 * 400
        + inequality_data.low_middle_40 * 400
        + bottom_10 * 90
        + bottom_1 * 9
        + bottom_0_1) / 1000) == round(M2_PER_CAPITA)
end