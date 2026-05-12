using Test
using DataFrames
using EconoSim

@testset "Calculate taxes - income tax" begin
    years = 1
    start_balance = 0
    gi = 1000
    income = 10000
    expenses = 9000

    taxes = calculate_taxes(years = years,
                            tax_type = INCOME_TAX,
                            tax_brackets = 0.1,
                            guaranteed_income = gi,
                            dem_free = 0,
                            demurrage = 0.1,
                            start_balance = start_balance,
                            income = income,
                            expenses = expenses,
                            transactional = false)
    @test taxes[!, :tax][1] == Currency(12000.0)
    @test taxes[!, :year_dem][1] == Currency(10366.1613)
    @test taxes[!, :balance][1] == Currency(1633.8387)
    @test taxes[!, :tax][1] + taxes[!, :year_dem][1] + taxes[!, :balance][1] == (gi + income - expenses) * 12

    years = 5
    taxes = calculate_taxes(years = years,
                            tax_type = INCOME_TAX,
                            tax_brackets = 0.1,
                            guaranteed_income = gi,
                            dem_free = 0,
                            demurrage = 0.1,
                            start_balance = start_balance,
                            income = income,
                            expenses = expenses,
                            transactional = false)
    
    for i in 1:years
        @test taxes[!, :tax][i] + taxes[!, :year_dem][i] + taxes[!, :balance][i] - start_balance == (gi + income - expenses) * 12
        start_balance = taxes[!, :balance][i]
    end
end

@testset "Calculate taxes - demurrage tax" begin
    years = 1
    start_balance = 0
    gi = 1000
    income = 10000
    expenses = 9000

    taxes = calculate_taxes(years = years,
                            tax_type = DEMURRAGE_TAX,
                            tax_brackets = 0.1,
                            guaranteed_income = gi,
                            dem_free = 0,
                            demurrage = 0.1,
                            start_balance = start_balance,
                            income = income,
                            expenses = expenses,
                            transactional = false)
    @test taxes[!, :tax][1] == Currency(7809.2376)
    @test taxes[!, :year_dem][1] == Currency(7809.2376)
    @test taxes[!, :balance][1] == Currency(8381.5248)
    @test taxes[!, :tax][1] + taxes[!, :year_dem][1] + taxes[!, :balance][1] == (gi + income - expenses) * 12

    years = 5
    taxes = calculate_taxes(years = years,
                            tax_type = DEMURRAGE_TAX,
                            tax_brackets = 0.1,
                            guaranteed_income = gi,
                            dem_free = 0,
                            demurrage = 0.1,
                            start_balance = 0,
                            income = income,
                            expenses = expenses,
                            transactional = false)
    
    for i in 1:years
        @test taxes[!, :tax][i] + taxes[!, :year_dem][i] + taxes[!, :balance][i] - start_balance == (gi + income - expenses) * 12
        start_balance = taxes[!, :balance][i]
    end
end