using EconoSim
using FixedPointDecimals

@enum Country BE NL
@enum WealthScale WS_WEALTH WS_MONEY_STOCK
@enum IncomeScale IS_INCOME IS_GDP
@enum AgeGroup POP_MIN_18 POP_18_TO_64 POP_65_PLUS

PopulationGroup = Union{AgeGroup, Nothing}

const MONTH = 1
const YEAR = 12

struct PopulationData
    population_dict::Dict{Symbol, Int}
    adjust_pop_up::Symbol
    adjust_pop_down::Symbol
end

function PopulationData(pop_min_18::Int,
                        pop_18_to_64::Int,
                        pop_65_plus::Int,
                        adjust_pop_up::AgeGroup = POP_65_PLUS,
                        adjust_pop_down::AgeGroup = POP_MIN_18)
    pop_dict = Dict{Symbol, Int}()
    pop_dict[Symbol(POP_MIN_18)] = pop_min_18
    pop_dict[Symbol(POP_18_TO_64)] = pop_18_to_64
    pop_dict[Symbol(POP_65_PLUS)] = pop_65_plus

    return PopulationData(pop_dict,
                            Symbol(adjust_pop_up),
                            Symbol(adjust_pop_down))
end

"""
    struct CivilianData
    * avg_gross_income::Currency
    * avg_cost_of_living::Currency
    * avg_rent::Currency
    * wealth_inequality::InequalityData
    * income_inequality::InequalityData

    All cost and income data is on monthly basis. 
"""
struct CivilianData{C <: FixedDecimal}
    avg_gross_income::C
    avg_cost_of_living::C
    avg_rent::C
    wealth_inequality::InequalityData{C}
    income_inequality::InequalityData{C}
    CivilianData(avg_gross_income::Real,
                avg_cost_of_living::Real,
                avg_rent::Real,
                wealth_inequality::InequalityData,
                income_inequality::InequalityData) = new{Currency}(avg_gross_income,
                                                                    avg_cost_of_living,
                                                                    avg_rent,
                                                                    wealth_inequality,
                                                                    income_inequality)
end

"""
    Data on government income and expenses. All data is on a monthly basis.
"""
struct GovernmentData{C <: FixedDecimal}
    gdp::C
    debt::C
    expenses::C
    interest_cost::C
    pension_cost::C
    unemployment_cost::C
    income::C
    vat_income::C
    income_tax_brackets::DemTiers
    GovernmentData(gdp::Real,
                    debt::Real,
                    expenses::Real,
                    interest_cost::Real,
                    pension_cost::Real,
                    unemployment_cost::Real,
                    income::Real,
                    vat_income::Real,
                    income_tax_brackets::DemSettings) = new{Currency}(gdp,
                                                                    debt,
                                                                    expenses,
                                                                    interest_cost,
                                                                    pension_cost,
                                                                    unemployment_cost,
                                                                    income,
                                                                    vat_income,
                                                                    make_tiers(income_tax_brackets))
end

struct SuMSyData{C <: FixedDecimal}
    flat_gi::C
    demurrage_free::C
    sumsy_groups::Dict{Symbol, Tuple{C, C}}
    interval::Int
end

function SuMSyData(flat_gi::Real,
                    demurrage_free::Real = 0;
                    gi_min_18::Real = flat_gi,
                    dem_free_min_18 = demurrage_free,
                    gi_18_to_64::Real = flat_gi,
                    dem_free_18_to_64 = demurrage_free,
                    gi_65_plus::Real = flat_gi,
                    dem_free_65_plus = demurrage_free,
                    interval::Int = MONTH)
    sumsy_groups = Dict{Symbol, Tuple{Real, Real}}()
    sumsy_groups[Symbol(POP_MIN_18)] = (gi_min_18, dem_free_min_18)
    sumsy_groups[Symbol(POP_18_TO_64)] = (gi_18_to_64, dem_free_18_to_64)
    sumsy_groups[Symbol(POP_65_PLUS)] = (gi_65_plus, dem_free_65_plus)

    return SuMSyData{Currency}(flat_gi, demurrage_free, sumsy_groups, interval)
end

struct CountryData{C <: FixedDecimal}
    country::Country
    year::Int
    money_stock::C
    population_data::PopulationData
    civilian_data::CivilianData{C}
    government_data::GovernmentData{C}
    sumsy_data::SuMSyData
    CountryData(country::Country,
                year::Int,
                money_stock::Real,
                population_data::PopulationData,
                civilian_data::CivilianData,
                government_data::GovernmentData,
                sumsy_data::SuMSyData) = new{Currency}(country,
                                                        year,
                                                        money_stock,
                                                        population_data,
                                                        civilian_data,
                                                        government_data,
                                                        sumsy_data)
end

const COUNTRY_DATA = Dict{Country, CountryData}()

function set_country_data(country_data::CountryData)
    COUNTRY_DATA[country_data.country] = country_data
end

function get_country_data(country::Country)
    return COUNTRY_DATA[country]
end

function get_m_per_capita(country::Country)
    return Currency(get_country_data(country).money_stock / get_population(country))
end

# Population data

function get_population(country::Country, population_group::PopulationGroup = nothing)
    if isnothing(population_group)
        pop_total = 0

        for population in values(get_country_data(country).population_data.population_dict)
            pop_total += population
        end

        return pop_total
    else
        return get_country_data(country).population_data.population_dict[Symbol(population_group)]
    end
end

function get_percentage_population(country::Country, population_group::PopulationGroup)
    return get_population(country, population_group) / get_population(country, nothing)
end

function adjust_population_up(country::Country)
    return get_country_data(country).population_data.adjust_pop_up
end

function adjust_population_down(country::Country)
    return get_country_data(country).population_data.adjust_pop_down
end

# Civilian data

function get_avg_gross_income(country::Country; period::Int = MONTH)
    return get_country_data(country).civilian_data.avg_gross_income * period
end

function get_avg_net_income(country::Country; period::Int = MONTH, tax_period::Int = YEAR)
    avg_gross_yearly_income = get_avg_gross_income(country, period = tax_period)
    income_tax_brackets = get_income_tax_brackets(country::Country)

    return Currency((avg_gross_yearly_income - calculate_time_range_demurrage(avg_gross_yearly_income, income_tax_brackets, 0, 1, 1, false))) * period / tax_period
end

function get_avg_cost_of_living(country::Country; period::Int = MONTH)
    return get_country_data(country).civilian_data.avg_cost_of_living * period
end

function get_avg_rent(country::Country; period::Int = MONTH)
    return get_country_data(country).civilian_data.avg_rent * period
end

function get_wealth_inequality(country::Country, scale::WealthScale = WS_MONEY_STOCK)
    if scale == WS_MONEY_STOCK
        return scale_inequality_data(get_country_data(country).civilian_data.wealth_inequality, get_m_per_capita(country))
    else
        return get_country_data(country).civilian_data.wealth_inequality
    end
end

function get_income_inequality(country::Country; scale::IncomeScale = IS_GDP, period::Int = MONTH)
    inequality_data = get_country_data(country).civilian_data.income_inequality

    inequality_data = InequalityData(isnothing(inequality_data.top_0_1) ? nothing : inequality_data.top_0_1 * period,
                                    isnothing(inequality_data.top_1) ? nothing : inequality_data.top_1 * period,
                                    inequality_data.top_10 * period,
                                    inequality_data.high_middle_40 * period,
                                    inequality_data.low_middle_40 * period,
                                    inequality_data.bottom_10 * period,
                                    isnothing(inequality_data.bottom_1) ? nothing : inequality_data.bottom_1 * period,
                                    isnothing(inequality_data.bottom_0_1) ? nothing : inequality_data.bottom_0_1 * period)

    if scale == IS_INCOME
        return inequality_data
    elseif scale == IS_GDP
        return scale_inequality_data(inequality_data, get_gdp_per_capita(country, period = period))
    end
end

# Government data

function get_gdp_per_capita(country::Country; period::Int = MONTH)
    return Currency(get_country_data(country).government_data.gdp * period / get_population(country))
end

function get_government_debt_per_capita(country::Country)
    return Currency(get_country_data(country).government_data.debt / get_population(country))
end

function get_expenses_per_capita(country::Country; period::Int = MONTH)
    return Currency(get_country_data(country).government_data.expenses * period / get_population(country))
end

function get_net_expenses_per_capita(country::Country; period::Int = MONTH)
    return get_expenses_per_capita(country, period = period) - get_interest_cost_per_capita(country, period = period)
end

function get_interest_cost_per_capita(country::Country; period::Int = MONTH)
    return Currency(get_country_data(country).government_data.interest_cost * period / get_population(country))
end

function get_pension_cost_per_capita(country::Country; period::Int = MONTH)
    return Currency(get_country_data(country).government_data.pension_cost * period / get_population(country))
end

function get_avg_pension(country::Country; period::Int = MONTH)
    return Currency(get_country_data(country).government_data.pension_cost * period / get_population(country, POP_65_PLUS))
end

function get_unemployment_cost_per_capita(country::Country; period::Int = MONTH)
    return Currency(get_country_data(country).government_data.unemployment_cost * period / get_population(country))
end

function get_income_per_capita(country::Country; period::Int = MONTH)
    return Currency(get_country_data(country).government_data.income * period / get_population(country))
end

function get_vat_income_per_capita(country::Country; period::Int = MONTH)
    return Currency(get_country_data(country).government_data.vat_income * period / get_population(country))
end

function get_income_tax_brackets(country::Country)
    return get_country_data(country).government_data.income_tax_brackets
end

function calculate_avg_vat(country::Country)
    return get_vat_income_per_capita(country, period = YEAR) / get_income_per_capita(country, period = YEAR)
end

function calculate_flat_gdp_tax(country::Country)
    return get_income_per_capita(country) / get_gdp_per_capita(country)
end

# SuMSy data

function get_flat_gi(country::Country; period::Int = MONTH)
    return get_country_data(country).sumsy_data.flat_gi * period
end

function get_demurrage_free(country::Country)
    return get_country_data(country).sumsy_data.demurrage_free
end

function get_gi(country::Country, age_group::AgeGroup; period::Int = MONTH)
    return get_country_data(country).sumsy_data.sumsy_groups[age_group][1] * period
end

function get_demurrage_free(country::Country, age_group::AgeGroup)
    return get_country_data(country).sumsy_data.sumsy_groups[age_group][2]
end

function get_sumsy_groups(country::Country; period::Int = MONTH)
    sumsy_groups = get_country_data(country).sumsy_data.sumsy_groups
    scaled_sumsy_groups = Dict{Symbol, Tuple{Real, Real}}()

    for age_symbol in keys(sumsy_groups)
        value = sumsy_groups[age_symbol]
        scaled_sumsy_groups[age_symbol] = (value[1] * period, value[2])
    end

    return scaled_sumsy_groups
end

function get_sumsy_expenses_per_capita(country::Country; period::Int = MONTH)
    return get_net_expenses_per_capita(country, period = period)
            - get_pension_cost_per_capita(country, period = period)
            - get_unemployment_cost_per_capita(country, period = period)
end

function calculate_demurrage(country::Country, flat_gi::Bool = true, period = MONTH)
    if flat_gi
        return make_tiers(get_flat_gi(country, period = period) / get_m_per_capita(country))
    else
        return make_tiers(((get_gi_min_18(country, period) * get_population(country, POP_MIN_18)
                            + get_gi_18_to_64(country, period) * get_population(country, POP_18_TO_64)
                            + get_gi_65_plus(country, period) * get_population(country, POP_65_PLUS))
                                / get_population(country)) / get_m_per_capita(country))
    end
end

function calculate_dem_tax(country::Country; period::Int = MONTH)
    return get_sumsy_expenses_per_capita(country, period = period) / get_m_per_capita(country)
end

function get_sumsy_interval(country::Country)
    return get_country_data(country).sumsy_data.interval
end