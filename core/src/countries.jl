# Country datasets and derivation rules.
#
# The values mirror MoneySim's `data_be.jl` / `country.ts`. Keeping the dataset
# upstream lets the wasm and native frontends derive the same config.
#
# This file is native-only for now: it is not reachable from the wasm ABI until
# the country entry points are added.

struct CountryPopulation
    min18::Int
    age18to64::Int
    age65plus::Int
end

struct CountryInequality
    top_0_1::Money
    top_1::Money
    top_10::Money
    high_middle_40::Money
    low_middle_40::Money
    bottom_10::Money
    bottom_1::Money
    bottom_0_1::Money
end

struct CountryCivilian
    avg_gross_income::Money
    avg_cost_of_living::Money
    avg_rent::Money
    wealth::CountryInequality
    income::CountryInequality
end

struct CountryGovernment
    gdp::Money
    debt::Money
    expenses::Money
    interest_cost::Money
    pension_cost::Money
    unemployment_cost::Money
    income::Money
    vat_income::Money
    tax_brackets::Vector{Money}
    tax_rates::Vector{Int64}
end

struct CountrySumsy
    flat_gi::Money
    demurrage_free::Money
    interval::Int
end

struct CountryData
    name::String
    year::Int
    money_stock::Money
    population::CountryPopulation
    civilian::CountryCivilian
    government::CountryGovernment
    sumsy::CountrySumsy
end

population_total(country::CountryData) =
    country.population.min18 + country.population.age18to64 +
    country.population.age65plus

money_per_capita(country::CountryData) =
    div(country.money_stock, population_total(country))

gdp_per_capita(country::CountryData) =
    div(country.government.gdp, population_total(country))

"""    belgium() -> CountryData

Belgium 2023, the paper-3 calibration dataset.
"""
function belgium()
    wealth = CountryInequality(
        money(8_938_739.974), money(3_811_778.9713),
        money(1_328_577.6418), money(255_669.2208),
        money(48_963.733), money(-768.0704),
        money(-42_489.2532), money(-42_489.2532))

    income = CountryInequality(
        money(929_099.2277 / 12), money(352_553.0531 / 12),
        money(133_618.6312 / 12), money(47_402.7566 / 12),
        money(20_266.3001 / 12), money(1_428.5148 / 12),
        money(0), money(0))

    government = CountryGovernment(
        money(596_321_000_000 / 12),
        money(614_991_000_000),
        money(317_595_000_000 / 12),
        money(11_926_000_000 / 12),
        money(62_900_000_000 / 12),
        money(6_400_000_000 / 12),
        money(292_624_000_000 / 12),
        money(37_828_100_000 / 12),
        [money(10_190), money(15_200), money(26_830), money(46_440)],
        Int64[0, 250_000, 400_000, 450_000, 500_000])

    return CountryData(
        "belgium", 2023, money(674_000_000_000),
        CountryPopulation(1_314_555 + 274_738 + 747_040,
                          4_029_828 + 804_889 + 2_215_697,
                          1_430_423 + 161_548 + 718_838),
        CountryCivilian(money(4_076), money(927.8), money(1_007), wealth, income),
        government,
        CountrySumsy(money(1_246.05), money(0), 1))
end

function _adjust_percentiles(low, mid, high)
    mid = div(10 * mid - low, 9)
    high = div(100 * high - 9 * mid - low, 90)
    return low, mid, high
end

"""
    unequal_wealth(country, actors) -> Vector{Money}

Distribute the country's wealth percentiles across `actors`, scaled so the
per-capita wealth equals `money_per_capita(country)`. Uses the full
0.1/1/10/40/40/10/1/0.1 percentile structure for runs of at least 1,000 actors.
"""
function _distribute_country(data::CountryInequality, actors::Int,
                            per_capita::Money)
    weighted = money(0)
    weighted += div(data.top_10, 10)
    weighted += div(data.high_middle_40 * 4, 10)
    weighted += div(data.low_middle_40 * 4, 10)
    weighted += div(data.bottom_10, 10)
    target = per_capita * actors

    scale = weighted == MONEY_ZERO ? 0.0 :
        Float64(per_capita.value) / Float64(weighted.value)

    function scaled(value::Money)
        return Money(round(Int64, Float64(value.value) * scale))
    end

    if actors < 1_000
        # Fall back to the four coarse groups for very small samples.
        bottom_count = max(1, round(Int, actors * 0.10))
        low_count = max(1, round(Int, actors * 0.40))
        high_count = max(1, round(Int, actors * 0.40))
        top_count = max(0, actors - bottom_count - low_count - high_count)
        values = Vector{Money}(undef, actors)
        index = 1
        for _ in 1:bottom_count
            values[index] = scaled(data.bottom_10); index += 1
        end
        for _ in 1:low_count
            values[index] = scaled(data.low_middle_40); index += 1
        end
        for _ in 1:high_count
            values[index] = scaled(data.high_middle_40); index += 1
        end
        for _ in 1:top_count
            values[index] = scaled(data.top_10); index += 1
        end
        _rescale_total!(values, target)
        return values
    end

    top_0_1, top_1, top_10 = _adjust_percentiles(data.top_0_1, data.top_1,
                                                 data.top_10)
    bottom_0_1, bottom_1, bottom_10 = _adjust_percentiles(data.bottom_0_1,
                                                          data.bottom_1,
                                                          data.bottom_10)

    n0_1 = max(1, round(Int, actors * 0.001))
    n1 = max(1, round(Int, actors * 0.01))
    n10 = max(1, round(Int, actors * 0.10))
    n50 = max(1, round(Int, actors * 0.50))
    n90 = max(1, round(Int, actors * 0.90))
    n99 = max(1, round(Int, actors * 0.99))
    n999 = max(1, round(Int, actors * 0.999))

    edges = (0, n0_1, n1, n10, n50, n90, n99, n999, actors)
    groups = (bottom_0_1, bottom_1, bottom_10, data.low_middle_40,
              data.high_middle_40, top_10, top_1, top_0_1)

    values = Vector{Money}(undef, actors)
    for group in 1:8
        value = scaled(groups[group])
        for index in (edges[group] + 1):edges[group + 1]
            values[index] = value
        end
    end

    _rescale_total!(values, target)
    return values
end

function _rescale_total!(values::Vector{Money}, target::Money)
    total = sum(values)
    delta, remainder = divrem(target.value - total.value, length(values))
    for i in eachindex(values)
        values[i] += Money(delta)
        if i <= remainder
            values[i] += Money(1)
        end
    end
    return values
end

unequal_wealth(country::CountryData, actors::Int) =
    _distribute_country(country.civilian.wealth, actors,
                        money_per_capita(country))

unequal_income(country::CountryData, actors::Int; period::Integer = 1) =
    _distribute_country(country.civilian.income, actors,
                        gdp_per_capita(country) * Int(period))

"""
    country_config(country; kwargs...) -> SimConfig

Derive a simulation config from a country dataset. Defaults follow the paper-3
setup: monthly steps, yearly recording, SUMSY with the country's flat GI and
demurrage, a GDP volume target, progressive income tax, and the government
sector. Override any group through the keyword arguments.
"""
function country_config(country::CountryData;
                        actors::Integer = 5_000,
                        periods::Integer = 120,
                        seed::Integer = 42,
                        wealth_distribution::WealthDistribution.Kind =
                            WealthDistribution.EQUAL,
                        tax_kind::TaxKind.Kind = TaxKind.INCOME,
                        tax_interval::Integer = 12,
                        target_revenue::Union{Nothing, Money} = nothing,
                        deficit_spending::Bool = false,
                        government_enabled::Bool = true,
                        gdp_growth_per_year::Real = 0.0,
                        wealth_advantage::Real = 0.035,
                        record_interval::Integer = 12)
    count = Int(actors)
    per_capita = money_per_capita(country)

    wealth = if wealth_distribution === WealthDistribution.CUSTOM
        WealthConfig(WealthDistribution.CUSTOM, MONEY_ZERO,
                     unequal_wealth(country, count))
    else
        WealthConfig(WealthDistribution.EQUAL, per_capita, Money[])
    end

    demurrage_rate = Float64(country.sumsy.flat_gi.value) /
                     Float64(per_capita.value)
    money = MoneyConfig(model = MoneyModel.SUMSY,
                        guaranteed_income = country.sumsy.flat_gi,
                        demurrage = make_tiers(demurrage_rate),
                        demurrage_free = country.sumsy.demurrage_free,
                        interval = country.sumsy.interval,
                        interest_rate = 0)

    transactions = TransactionConfig(enabled = false,
                                     transactions_per_step = 0,
                                     transfer_rate = 0.2,
                                     wealth_advantage = wealth_advantage)

    tax = if tax_kind === TaxKind.INCOME
        rates = copy(country.government.tax_rates)
        brackets = Vector{Money}(undef, length(country.government.tax_brackets) + 1)
        for i in eachindex(country.government.tax_brackets)
            brackets[i] = country.government.tax_brackets[i]
        end
        brackets[end] = typemax(Money)
        target = target_revenue === nothing ?
            div(country.government.income * count, population_total(country)) :
            target_revenue
        TaxConfig(kind = TaxKind.INCOME, interval = tax_interval,
                  recipient = TaxRecipient.EVERYONE,
                  brackets = brackets, bracket_rates = rates,
                  target_revenue = target,
                  scale_to_target = target > MONEY_ZERO,
                  notional = unequal_income(country, count; period = tax_interval))
    else
        TaxConfig(kind = TaxKind.NONE)
    end

    expenses = government_enabled ?
        div(country.government.expenses * count, population_total(country)) :
        MONEY_ZERO
    government = GovernmentConfig(enabled = government_enabled,
                                  expenses = expenses,
                                  deficit_spending = deficit_spending,
                                  initial_debt = div(country.government.debt * count,
                                                     population_total(country)))

    gdp = GdpConfig(enabled = true, per_capita = gdp_per_capita(country),
                    growth_ppm = ppm(gdp_growth_per_year),
                    interval = 1)

    return SimConfig(periods = periods, seed = seed,
                     record_interval = record_interval,
                     money = money, wealth = wealth,
                     transactions = transactions, tax = tax,
                     population = PopulationConfig(count = count),
                     government = government, gdp = gdp, adaptations = AdaptationConfig(),
                     bank = BankConfig(), loan_circuit = LoanCircuitConfig())
end

export CountryPopulation, CountryInequality, CountryCivilian
export CountryGovernment, CountrySumsy, CountryData
export population_total, money_per_capita, gdp_per_capita
export belgium, unequal_wealth, unequal_income, country_config
