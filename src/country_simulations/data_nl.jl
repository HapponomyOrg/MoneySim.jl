const M2_NL = Currency(1120000000000)
# Average of year 2023
# Source https://tradingeconomics.com/netherlands/money-supply-m2

const M3_NL = Currency(1129000000000)
# Average of year 2023
# Source https://tradingeconomics.com/netherlands/money-supply-m3

# Source https://wid.world - Belgium, 2023, Euro (accessed on 28-03-2026)

# Denmark
# -292.2305
# 162.9019
# 25014.4153
# 286508.903
# 1253942.3407
# 5140851.0359
# 25919030.1735
# 146083232.5275

# Sweden
# -230014.887
# -19305.2677
# -9068.5742
# 205973.6595
# 1305403.9603
# 5186472.0653
# 25519813.6295
# 166896294.6405

function set_country_data_nl()
    income_tax_brackets = [(0, 0)]
    # Source: 

    pop_min_18 = 3313000
    pop_18_to_64 = 10892000
    pop_65_plus = 3703000
    # Source https://www.cbs.nl/nl-nl/visualisaties/dashboard-bevolking/bevolkingspiramide - accessed 28-03-2026

    population_data = PopulationData(pop_min_18, pop_18_to_64, pop_65_plus)

    avg_gross_income = 0
    # Source: 

    avg_cost_of_living = 0
    # Source = 
 
    avg_rent = 0
    # Source: 

    living_wage_cat1 = CUR_0 # Living together
    living_wage_cat2 = CUR_0 # Living alone
    living_wage_cat3 = CUR_0 # Living together with family burden
    # Source: 

    child_benefits = 0
    # Source:

    avg_living_wage = Currency((living_wage_cat1 + living_wage_cat2 + living_wage_cat3) / 3)

    wealth_inequality = InequalityData(11162034.2944,    # Top 0.1%
                                        3569809.2522,    # Top 1%
                                        1168502.7021,    # Top 10%
                                        287145.794,      # High middle 40%
                                        59219.1173,      # Low middle 40%
                                        1659.6765,       # Bottom 10%
                                        -5394.8663,      # Bottom 1%
                                        nothing)         # Bottom 0.1% - data not available

    income_inequality = InequalityData(0 / 12,    # Top 0.1%
                                        0 / 12,   # Top 1%
                                        0 / 12,   # Top 10%
                                        0 / 12,    # High middle 40%
                                        0 / 12,    # Low middle 40%
                                        0 / 12,     # Bottom 10%
                                        0,                  # Bottom 1%
                                        nothing)            # Bottom 0.1% - data not available
    # Source: 

    civilian_data = CivilianData(avg_gross_income,
                                avg_cost_of_living,
                                avg_rent,
                                wealth_inequality,
                                income_inequality)

    gdp = 0
    gov_income = 0
    gov_expenses = 0
    gov_debt = 0
    gov_interest_cost = 0
    # Source: 

    gov_vat_income = 0 # 2023
    # Source: 

    gov_pension_cost = 0
    gov_unemployment_cost = 0
    # Source: 

    government_data = GovernmentData(gdp / 12,
                                    gov_debt,
                                    gov_expenses / 12,
                                    gov_interest_cost / 12,
                                    gov_pension_cost / 12,
                                    gov_unemployment_cost / 12,
                                    gov_income / 12,
                                    gov_vat_income / 12,
                                    income_tax_brackets)

    sumsy_data = SuMSyData(avg_living_wage,
                            0,
                            gi_min_18 = child_benefits,
                            gi_18_to_64 = avg_living_wage,
                            gi_65_plus = gov_pension_cost / pop_65_plus) # Set to average pension.

    m2 = Currency(1120000000000)
    # Average of year 2023
    # Source https://tradingeconomics.com/netherlands/money-supply-m2

    m3 = Currency(1129000000000)
    # Average of year 2023
    # Source https://tradingeconomics.com/netherlands/money-supply-m3

    country_data = CountryData(NL,
                                2023,
                                m3,
                                population_data,
                                civilian_data,
                                government_data,
                                sumsy_data)
    set_country_data(country_data)
end

set_country_data_nl()