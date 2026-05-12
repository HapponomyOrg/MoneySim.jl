const M2_NL = Currency(1120000000000)
# Average of year 2023
# Source https://tradingeconomics.com/netherlands/money-supply-m2

const M3_NL = Currency(1129000000000)
# Average of year 2023
# Source https://tradingeconomics.com/netherlands/money-supply-m3

const POP_MIN_18_NL = 3313000
const POP_18_TO_64_NL = 10892000
const POP_65_PLUS_NL = 3703000
const POPULATION_NL = POP_MIN_18_NL + POP_18_TO_64_NL + POP_65_PLUS_NL
# Source https://www.cbs.nl/nl-nl/visualisaties/dashboard-bevolking/bevolkingspiramide - accessed 28-03-2026

const PERCENT_MIN_18_NL = POP_MIN_18_NL / POPULATION_NL
const PERCENT_18_TO_64_NL = POP_18_TO_64_NL / POPULATION_NL
const PERCENT_65_PLUS_NL = POP_65_PLUS_NL / POPULATION_NL

# Netherlands
# 5394.8663
# 1659.6765
# 59219.1173
# 287145.794
# 1168502.7021
# 3569809.2522
# 11162034.2944
# 44186279.9754

const WEALTH_INEQUALITY_DATA_NL = InequalityData(11162034.2944,    # Top 0.1%
                                        3569809.2522,                # Top 1%
                                        1168502.7021,                # Top 10%
                                        287145.794,                 # High middle 40%
                                        59219.1173,                  # Low middle 40%
                                        1659.6765,                   # Bottom 10%
                                        -5394.8663,                  # Bottom 1%
                                        nothing)                # Bottom 0.1% - data not available
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