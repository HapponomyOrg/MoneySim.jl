function set_country_data_test()
    income_tax_brackets = [(0.1, 0.25), (15200, 0.4), (26830, 0.45), (46440, 0.5)]
    # Source https://financien.belgium.be/nl/particulieren/belastingaangifte/belastingtarieven-inkomen/belastingtarieven#q1

    pop_min_18 = 1997
    pop_18_to_64 = 6028 # Flanders + Brussels + Wallonia
    pop_65_plus = 1975
    # Source: https://bestat.statbel.fgov.be/bestat/crosstable.xhtml?view=161080d2-d411-4e40-9a0f-a27db5e2b6e1

    population_data = PopulationData(pop_min_18, pop_18_to_64, pop_65_plus)

    avg_gross_income = 4076
    # Source: https://statbel.fgov.be/nl/themas/werk-opleiding/lonen-en-arbeidskosten/gemiddelde-bruto-maandlonen

    avg_cost_of_living = 927.80
    # Source = https://werelddata.nl/kosten-van-levensonderhoud/belgie#:~:text=In%20het%20kort,5.1%25%20lager%20dan%20in%20Nederland.
 
    avg_rent = 1007
    # Source: https://www.livios.be/nl/artikel/100605/problemen-op-de-huurmarkt-stijgende-huurprijzen-en-tekort-aan-huurwoningen/#:~:text=Huren%20is%20er%20ook%20niet,gemiddeld%20841%20euro%20per%20maand.

    living_wage_cat1 = Currency((809.42 + 825.61 + 842.12) / 3) # Living together
    living_wage_cat2 = Currency((1214.13 + 1238.41 + 1263.17) / 3) # Living alone
    living_wage_cat3 = Currency((1640.83 + 1673.65 + 1707.11) / 3) # Living together with family burden
    # Source: https://primabook.mi-is.be/nl/recht-op-maatschappelijke-integratie/bedragen-leefloon

    child_benefits = 200
    # Source: https://www.groeipakket.be/bedragen - rounded up to account for Belgian complexity.

    avg_living_wage = Currency((living_wage_cat1 + living_wage_cat2 + living_wage_cat3) / 3)

    wealth_inequality = InequalityData(143073148.7596,     # Top 0.1%
                                        14329991.1801,   # Top 1%
                                        1452061.828,   # Top 10%
                                        -7606.6113,    # High middle 40%
                                        -117604.4189,      # Low middle 40%
                                        -329321.0518,      # Bottom 10%
                                        -494138.581,    # Bottom 1%
                                        -601210.256)        # Bottom 0.1% - data not available

    income_inequality = InequalityData(17144057.3516 / 12,    # Top 0.1%
                                        3700836.7833 / 12,   # Top 1%
                                        1635714.4307 / 12,   # Top 10%
                                        745870.7682 / 12,    # High middle 40%
                                        394412.1345 / 12,    # Low middle 40%
                                        35754.5811 / 12,     # Bottom 10%
                                        0,                  # Bottom 1%
                                        0)            # Bottom 0.1% - data not available
    # Source https://wid.world - Belgium, 2023, Euro (accessed on 28-03-2026)

    civilian_data = CivilianData(avg_gross_income,
                                avg_cost_of_living,
                                avg_rent,
                                wealth_inequality,
                                income_inequality)

    gdp = 15471873.4903
    gov_income = 306933089.6134
    gov_expenses = 271505432.4168
    gov_debt = 190740263.4067
    gov_interest_cost = 11926000000
    # Source: https://www.nbb.be/doc/dq/n/dq3/histo/nndb2410.pdf

    gov_vat_income = 37828100000 # 2023
    # Source https://dataexplorer.nbb.be/vis?tm=vat&pg=0&snb=13&df[ds]=disseminate&df[id]=DF_NFGOVTSC_DISS&df[ag]=BE2&df[vs]=1.0&dq=A..S1300&lom=LASTNPERIODS&lo=6&to[TIME_PERIOD]=false

    gov_pension_cost = 62900000000
    gov_unemployment_cost = 6400000000
    # Source: https://www.ccrek.be/sites/default/files/Docs/181e_b_II_SocZk.pdf

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

    m2 = Currency(639000000000)
    # Average of year 2023
    # Source: https://tradingeconomics.com/belgium/money-supply-M

    m3 = Currency(674000000000)
    # Average of year 2023
    # Source: https://tradingeconomics.com/belgium/money-supply-m3

    country_data = CountryData(TEST,
                                2023,
                                m3,
                                population_data,
                                civilian_data,
                                government_data,
                                sumsy_data)
    set_country_data(country_data)
end

set_country_data_test()