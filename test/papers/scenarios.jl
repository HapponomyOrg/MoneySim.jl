# Canonical, backend-agnostic scenario manifest for the paper regression suite.
#
# This file contains DATA ONLY:
#   - no imports from MoneySim or MoneySimCore
#   - no simulation calls
#   - no assertions
#
# Both the legacy adapter (current MoneySim API) and the core adapter
# (post-refactor MoneySimCore) consume the same entries. That is what makes the
# before/after comparison meaningful.
#
# Symbolic bounds are resolved by the runner against the model helpers:
#   :telo_gi      => telo(GI, tiers) * N_GI
#   :telo_gi_df   => telo(GI, tiers, demurrage_free) * N_GI
#   :telo_total   => telo(GI * N_GI, tiers)
#   :telo_equal   => telo(GI_eq, tiers) * (N_GI + noneligible)
# where GI_eq = GI * N_GI / (N_GI + noneligible).
#
# Expected paper 1 values are the last printed ratios in the notebook.
# Expected paper 3 values are the final rows of the committed CSV fixtures.

# ---------------------------------------------------------------------------
# Paper 1 — Post-Keynesian endogenous money
# ---------------------------------------------------------------------------

const PAPER1_SCENARIOS = [
    (
        name = :baseline_g0_p0,
        description = "No growth, no profit",
        kind = :fixed_g,
        params = (g = 0.0, p = 0.0, m = 20, cycles = 100),
        expected = (debt_ratio_pct = 100.00,),
    ),
    (
        name = :growth_only_g005_p0,
        description = "Growth without profit",
        kind = :fixed_g,
        params = (g = 0.05, p = 0.0, m = 20, cycles = 100),
        expected = (debt_ratio_pct = 100.00,),
    ),
    (
        name = :p_less_than_g_short,
        description = "p < g, 100 cycles",
        kind = :fixed_g,
        params = (g = 0.05, p = 0.01, m = 20, cycles = 100),
        expected = (debt_ratio_pct = 124.49,),
    ),
    (
        name = :p_less_than_g_long,
        description = "p < g, 500 cycles, converges to g/(g-p)",
        kind = :fixed_g,
        params = (g = 0.05, p = 0.01, m = 20, cycles = 500),
        expected = (debt_ratio_pct = 125.00,),
    ),
    (
        name = :p_equals_g,
        description = "p = g, linear debt ratio",
        kind = :fixed_g,
        params = (g = 0.05, p = 0.05, m = 20, cycles = 100),
        expected = (debt_ratio_pct = 576.19,),
    ),
    (
        name = :p_greater_than_g,
        description = "p > g, unbounded debt ratio",
        kind = :fixed_g,
        params = (g = 0.05, p = 0.10, m = 20, cycles = 100),
        expected = (debt_ratio_pct = 20858.91,),
    ),
    (
        name = :maturity_independence,
        description = "Maturity does not change the fixed-growth ratio",
        kind = :fixed_g,
        params = (g = 0.05, p = 0.01, m = 40, cycles = 100),
        expected = (debt_ratio_pct = 124.49,),
    ),
    (
        name = :chart_parameter,
        description = "Parameter used for the paper's debt-ratio chart",
        kind = :fixed_g,
        params = (g = 0.0475, p = 0.008, m = 20, cycles = 500),
        expected = (debt_ratio_pct = 120.25,),
    ),
    (
        name = :loan_rate_stable,
        description = "Fixed loan rate, stable trajectory",
        kind = :fixed_lr,
        params = (LR = 0.15, p = 0.008, m = 20, cycles = 500),
        expected = (length = 500, growth_ratio_pct = 4.75, debt_ratio_pct = 120.25),
    ),
    (
        name = :loan_rate_collapse_m20,
        description = "Fixed loan rate, run collapses before 500 cycles",
        kind = :fixed_lr,
        params = (LR = 0.15, p = 0.009, m = 20, cycles = 500),
        expected = (length = 193, growth_ratio_pct = -66.68, debt_ratio_pct = 1528.12,
                    baseline_debt_ratio_pct = 1528.11),
    ),
    (
        name = :loan_rate_collapse_lr0149_m20,
        description = "Lower loan rate still collapses with maturity 20",
        kind = :fixed_lr,
        params = (LR = 0.149, p = 0.008, m = 20, cycles = 500),
        expected = (length = 476, growth_ratio_pct = -69.67, debt_ratio_pct = 1736.44,
                    baseline_debt_ratio_pct = 1736.48),
    ),
    (
        name = :loan_rate_stable_m30,
        description = "Longer maturity stabilises the same loan rate",
        kind = :fixed_lr,
        params = (LR = 0.149, p = 0.008, m = 30, cycles = 500),
        expected = (length = 500, growth_ratio_pct = 10.77, debt_ratio_pct = 108.02),
    ),
    (
        name = :random_growth_negative_relative_p,
        description = "Random growth, p below the realised growth",
        kind = :random_g,
        params = (min_g = 0.02, max_g = 0.12, relative_p = -0.05, m = 20, cycles = 500, no_loss = true),
        expected = (finite = true, length = 500),
    ),
    (
        name = :random_growth_zero_relative_p,
        description = "Random growth, p equal to the realised growth",
        kind = :random_g,
        params = (min_g = 0.02, max_g = 0.12, relative_p = 0.0, m = 20, cycles = 500, no_loss = true),
        expected = (finite = true, length = 500),
    ),
    (
        name = :random_growth_positive_relative_p,
        description = "Random growth, p above the realised growth",
        kind = :random_g,
        params = (min_g = 0.02, max_g = 0.12, relative_p = 0.05, m = 20, cycles = 500, no_loss = true),
        expected = (finite = true, length = 500),
    ),
]

# ---------------------------------------------------------------------------
# Paper 2 — Alternative general-purpose money supply (SUMSY)
# ---------------------------------------------------------------------------

const PAPER2_COMMON = (
    gi = 2000.0,
    demurrage = 0.01,
    demurrage_free = 0.0,
    demurrage_tiers = nothing,
    interval = 30,
    eligible = 100,
    noneligible = 0,
    transactions = 200,
    periods = 150,
    distributed = true,
    adaptation = :none,
)

const PAPER2_SCENARIOS = [
    (
        name = :a1,
        description = "Equal initial distribution",
        kind = :sumsy,
        params = PAPER2_COMMON,
        expected = (money_stock_target = 20_000_000.0),
    ),
    (
        name = :a2,
        description = "Initially concentrated",
        kind = :sumsy,
        params = merge(PAPER2_COMMON, (; distributed = false)),
        expected = (money_stock_target = 20_000_000.0),
    ),
    (
        name = :b1,
        description = "25 non-eligible accounts, equal distribution",
        kind = :sumsy,
        params = merge(PAPER2_COMMON, (; noneligible = 25)),
        expected = (money_stock_target = 20_000_000.0),
    ),
    (
        name = :b2,
        description = "25 non-eligible accounts, concentrated",
        kind = :sumsy,
        params = merge(PAPER2_COMMON, (; noneligible = 25, distributed = false)),
        expected = (money_stock_target = 20_000_000.0),
    ),
    (
        name = :s1,
        description = "One-off money injection",
        kind = :sumsy,
        params = merge(PAPER2_COMMON, (; periods = 750, adaptation = :one_time_injection)),
        expected = (money_stock_target = 20_000_000.0),
    ),
    (
        name = :s2,
        description = "Continuous money injection",
        kind = :sumsy,
        params = merge(PAPER2_COMMON, (; periods = 750, adaptation = :constant_injection)),
        expected = (
            money_stock_min = 20_000_000.0,
            money_stock_max = 30_000_000.0,
            money_stock_target = 30_000_000.0,
        ),
    ),
    (
        name = :s3,
        description = "One-off money destruction",
        kind = :sumsy,
        params = merge(PAPER2_COMMON, (; periods = 750, adaptation = :one_time_destruction)),
        expected = (money_stock_target = 20_000_000.0),
    ),
    (
        name = :s4,
        description = "Continuous money destruction",
        kind = :sumsy,
        params = merge(PAPER2_COMMON, (; periods = 750, adaptation = :constant_destruction)),
        expected = (
            money_stock_min = 10_000_000.0,
            money_stock_max = 20_000_000.0,
            money_stock_target = 10_000_000.0,
        ),
    ),
    (
        name = :e1,
        description = "Demurrage-free buffer of 25,000",
        kind = :sumsy,
        params = merge(PAPER2_COMMON, (; periods = 750, demurrage_free = 25_000.0)),
        expected = (
            money_stock_min = 20_000_000.0,
            money_stock_max = :telo_gi_df,
        ),
    ),
    (
        name = :e2,
        description = "Tiered demurrage",
        kind = :sumsy,
        params = merge(
            PAPER2_COMMON,
            (;
                periods = 750,
                demurrage_tiers = (
                    (0.0, 0.01),
                    (50_000.0, 0.02),
                    (500_000.0, 0.05),
                    (1_000_000.0, 0.10),
                    (10_000_000.0, 0.50),
                    (50_000_000.0, 0.95),
                ),
            ),
        ),
        expected = (
            money_stock_min = :telo_total,
            money_stock_max = :telo_gi,
        ),
    ),
    (
        name = :e3,
        description = "Tiered demurrage, no transactions, 25 non-eligible",
        kind = :sumsy,
        params = merge(
            PAPER2_COMMON,
            (;
                periods = 750,
                noneligible = 25,
                transactions = 0,
                adaptation = :equal_distribution,
                demurrage_tiers = (
                    (0.0, 0.01),
                    (50_000.0, 0.02),
                    (500_000.0, 0.05),
                    (1_000_000.0, 0.10),
                    (10_000_000.0, 0.50),
                    (50_000_000.0, 0.95),
                ),
            ),
        ),
        expected = (
            money_stock_min = :telo_total,
            money_stock_max = :telo_equal,
        ),
    ),
    (
        name = :e4,
        description = "Tiered demurrage, known non-eligible accounts",
        kind = :sumsy,
        params = merge(
            PAPER2_COMMON,
            (;
                periods = 750,
                noneligible = 25,
                transactions = 0,
                adaptation = :equal_distribution,
                demurrage_tiers = (
                    (0.0, 0.01),
                    (50_000.0, 0.02),
                    (500_000.0, 0.05),
                    (1_000_000.0, 0.10),
                    (10_000_000.0, 0.50),
                    (50_000_000.0, 0.95),
                ),
            ),
        ),
        expected = (
            money_stock_min = :telo_total,
            money_stock_max = :telo_equal,
        ),
    ),
    (
        name = :e5,
        description = "Tiered demurrage, realistic non-eligible share",
        kind = :sumsy,
        params = merge(
            PAPER2_COMMON,
            (;
                periods = 750,
                noneligible = 25,
                transactions = 200,
                demurrage_tiers = (
                    (0.0, 0.01),
                    (50_000.0, 0.02),
                    (500_000.0, 0.05),
                    (1_000_000.0, 0.10),
                    (10_000_000.0, 0.50),
                    (50_000_000.0, 0.95),
                ),
            ),
        ),
        expected = (
            money_stock_min = :telo_total,
            money_stock_max = :telo_equal,
        ),
    ),
    (
        name = :d1,
        description = "Transactional demurrage",
        kind = :sumsy,
        params = merge(PAPER2_COMMON, (; periods = 750, transactional = true)),
        expected = (finite = true, money_stock_positive = true),
    ),
]

# Consumer-supplier experiments (paper 2, section r1/r2).
const PAPER2_CONSUMER_SUPPLIER = [
    (
        name = :r1,
        description = "Consumer–supplier, flat demurrage",
        kind = :consumer_supplier,
        params = (gi = 2000.0, demurrage_free = 0.0, demurrage = 0.01,
                  demurrage_tiers = nothing, interval = 30, periods = 1500),
        cases = (
            (consumers = 50, fulfilled_demand = 5, net_profit = 1, expected_balance = 742_354.42),
            (consumers = 100, fulfilled_demand = 5, net_profit = 1, expected_balance = 1_484_708.83),
            (consumers = 100, fulfilled_demand = 3, net_profit = 2, expected_balance = 1_781_650.60),
        ),
    ),
    (
        name = :r2,
        description = "Consumer–supplier, tiered demurrage",
        kind = :consumer_supplier,
        params = (
            gi = 2000.0,
            demurrage_free = 0.0,
            demurrage = nothing,
            demurrage_tiers = (
                (0.0, 0.01),
                (50_000.0, 0.02),
                (500_000.0, 0.05),
                (1_000_000.0, 0.10),
                (10_000_000.0, 0.50),
                (50_000_000.0, 0.95),
            ),
            interval = 30,
            periods = 1500,
        ),
        cases = (
            (consumers = 50, fulfilled_demand = 5, net_profit = 1, expected_balance = 392_749.90),
            (consumers = 100, fulfilled_demand = 5, net_profit = 1, expected_balance = 595_500.00),
            (consumers = 100, fulfilled_demand = 3, net_profit = 2, expected_balance = 652_600.00),
        ),
    ),
]

# ---------------------------------------------------------------------------
# Paper 3 — Belgium inequality
# ---------------------------------------------------------------------------

const PAPER3_COMMON = (
    country = :be,
    years = 100,
    actors = 10_000,
    monetary_type = :fixed,       # :fixed | :sumsy
    taxes = :none,                # :none | :income | :demurrage | :gdp_flat
    gdp_growth_per_year = 0.0,
    vat = false,
    deduct_vat = false,
    deficit_spending = false,
    cover_expenses = false,
    scale_tax = false,
    tax_interval = :month,
    zeta = 0.035,
    population_type = :fixed,
    wealth_distribution = :unequal,
    wealth_transfer = 0.2,
    gdp_scaling = 1.0,
)

# Final reference values from jupyter/paper 3/data/<scenario>/.
# gini_income = nothing means the CSV reports NaN (no income in the window).
function _paper3(name, overrides, expected)
    (
        name = name,
        kind = :country,
        params = merge(PAPER3_COMMON, overrides),
        expected = expected,
        fixture = "jupyter/paper 3/data/" * String(name),
    )
end

const PAPER3_SCENARIOS = [
    _paper3(:a1, (; monetary_type = :sumsy),
        (gini_wealth = 0.4460, gini_income = 0.3619, money_stock = 576_874_999.9996,
         debt = 525_743_155.0, tax_scale = nothing,
         top10_share = 31.3803, bottom50_share = 19.4644,
         income_top10_share = 24.9067, income_bottom50_share = 24.5937)),
    _paper3(:a2, (; monetary_type = :sumsy, taxes = :demurrage, cover_expenses = true),
        (gini_wealth = 0.2677, gini_income = 0.3092, money_stock = 576_874_999.9775,
         debt = 525_743_155.0, tax_scale = 1.0,
         top10_share = 20.1480, bottom50_share = 31.0026,
         income_top10_share = 21.5273, income_bottom50_share = 28.0949)),
    _paper3(:a3, (; monetary_type = :sumsy, taxes = :income, cover_expenses = true,
                  scale_tax = true, tax_interval = :year),
        (gini_wealth = 0.3164, gini_income = 0.2013, money_stock = 576_859_072.2106,
         debt = 525_743_155.0, tax_scale = 1.4789,
         top10_share = 22.2478, bottom50_share = 27.6884,
         income_top10_share = 16.9057, income_bottom50_share = 35.8901)),
    _paper3(:a4, (; monetary_type = :sumsy, taxes = :demurrage, gdp_growth_per_year = -0.01),
        (gini_wealth = 0.1673, gini_income = 0.4350, money_stock = 576_874_999.9999,
         debt = 525_743_155.0, tax_scale = 1.0,
         top10_share = 15.9273, bottom50_share = 38.1428,
         income_top10_share = 26.9023, income_bottom50_share = 19.0953)),
    _paper3(:a5, (; monetary_type = :sumsy, taxes = :demurrage, gdp_growth_per_year = 0.01),
        (gini_wealth = 0.4409, gini_income = 0.2984, money_stock = 576_875_000.0025,
         debt = 525_743_155.0, tax_scale = 1.0,
         top10_share = 30.5731, bottom50_share = 19.6071,
         income_top10_share = 21.3978, income_bottom50_share = 28.7793)),
    _paper3(:a6, (; monetary_type = :sumsy, taxes = :demurrage, gdp_growth_per_year = 0.01,
                  vat = true, deduct_vat = true),
        (gini_wealth = 0.4453, gini_income = 0.2986, money_stock = 576_875_000.0003,
         debt = 525_743_155.0, tax_scale = 1.0,
         top10_share = 30.8126, bottom50_share = 19.2496,
         income_top10_share = 21.3487, income_bottom50_share = 28.6902)),
    _paper3(:a7, (; monetary_type = :sumsy, taxes = :demurrage, gdp_growth_per_year = 0.01,
                  vat = true, deduct_vat = false),
        (gini_wealth = 0.4123, gini_income = 0.2806, money_stock = 576_875_000.0006,
         debt = 525_743_155.0, tax_scale = 1.0,
         top10_share = 28.8299, bottom50_share = 21.4740,
         income_top10_share = 20.4986, income_bottom50_share = 30.0104)),
    _paper3(:a8, (; monetary_type = :sumsy, taxes = :income, gdp_growth_per_year = 0.01,
                  scale_tax = true, tax_interval = :year),
        (gini_wealth = 0.5932, gini_income = 0.3441, money_stock = 576_851_774.2811,
         debt = 525_743_155.0, tax_scale = 0.4185,
         top10_share = 45.0732, bottom50_share = 11.7446,
         income_top10_share = 24.3317, income_bottom50_share = 25.7878)),
    _paper3(:a9, (; monetary_type = :sumsy, taxes = :income, scale_tax = true,
                  tax_interval = :year, zeta = 0.5),
        (gini_wealth = 0.5607, gini_income = 0.3116, money_stock = 576_808_252.1200,
         debt = 525_743_155.0, tax_scale = 1.3851,
         top10_share = 45.1813, bottom50_share = 14.6084,
         income_top10_share = 24.9222, income_bottom50_share = 29.0820)),
    _paper3(:a10, (; monetary_type = :sumsy, taxes = :demurrage, cover_expenses = true,
                   scale_tax = true, tax_interval = :year, zeta = 0.5),
        (gini_wealth = 0.5312, gini_income = 0.4482, money_stock = 576_874_708.4396,
         debt = 525_743_155.0, tax_scale = 0.9988,
         top10_share = 42.2322, bottom50_share = 16.1213,
         income_top10_share = 33.2513, income_bottom50_share = 20.1529)),
    _paper3(:b1, (; years = 30, monetary_type = :fixed, taxes = :none),
        (gini_wealth = 1.0032, gini_income = nothing, money_stock = 576_188_734.7160,
         debt = 525_743_155.0, tax_scale = nothing,
         top10_share = 100.1668, bottom50_share = -0.1668,
         income_top10_share = 0.0, income_bottom50_share = 0.0)),
    _paper3(:c1, (; monetary_type = :fixed, taxes = :income, deficit_spending = true,
                  cover_expenses = false, scale_tax = true, tax_interval = :year,
                  vat = true, deduct_vat = true),
        (gini_wealth = 0.4251, gini_income = 0.3366, money_stock = 1_655_836_839.3117,
         debt = 1_605_391_259.5957, tax_scale = 1.3630,
         top10_share = 34.3732, bottom50_share = 22.8100,
         income_top10_share = 22.6952, income_bottom50_share = 26.6302)),
    _paper3(:c2, (; monetary_type = :fixed, taxes = :income, cover_expenses = true,
                  scale_tax = true, tax_interval = :year),
        (gini_wealth = 0.7554, gini_income = 0.2377, money_stock = 576_188_734.7160,
         debt = 525_743_155.0, tax_scale = 1.4626,
         top10_share = 66.1110, bottom50_share = 7.1977,
         income_top10_share = 18.4420, income_bottom50_share = 33.4182)),
    _paper3(:c3, (; monetary_type = :fixed, taxes = :income, gdp_growth_per_year = -0.01,
                  cover_expenses = true, scale_tax = true, tax_interval = :year),
        (gini_wealth = 0.4336, gini_income = 0.1754, money_stock = 576_188_734.7160,
         debt = 525_743_155.0, tax_scale = 6.6605,
         top10_share = 35.9563, bottom50_share = 22.9151,
         income_top10_share = 13.4333, income_bottom50_share = 38.6584)),
    _paper3(:c4, (; monetary_type = :fixed, taxes = :income, gdp_growth_per_year = 0.01,
                  cover_expenses = true, scale_tax = true, tax_interval = :year),
        (gini_wealth = 2.7459, gini_income = 0.8262, money_stock = 576_188_734.7160,
         debt = 525_743_155.0, tax_scale = 0.4429,
         top10_share = 199.9196, bottom50_share = -97.7330,
         income_top10_share = 64.6624, income_bottom50_share = 0.0)),
    _paper3(:c5, (; monetary_type = :fixed, taxes = :income, cover_expenses = true,
                  scale_tax = true, tax_interval = :year, zeta = 0.5),
        (gini_wealth = 0.8847, gini_income = 0.2856, money_stock = 576_188_734.7160,
         debt = 525_743_155.0, tax_scale = 1.4370,
         top10_share = 79.2625, bottom50_share = 1.5085,
         income_top10_share = 20.2053, income_bottom50_share = 30.2258)),
    _paper3(:u1, (; monetary_type = :fixed, taxes = :gdp_flat, tax_interval = :month),
        (gini_wealth = 0.8905, gini_income = 0.2316, money_stock = 576_188_734.7160,
         debt = 525_743_155.0, tax_scale = 1.0,
         top10_share = 87.2264, bottom50_share = 3.9946,
         income_top10_share = 20.3538, income_bottom50_share = 34.2234)),
]

# Convenience views used by the runner.
const ALL_PAPER_SCENARIOS = (
    paper1 = PAPER1_SCENARIOS,
    paper2 = PAPER2_SCENARIOS,
    paper2_consumer_supplier = PAPER2_CONSUMER_SUPPLIER,
    paper3 = PAPER3_SCENARIOS,
)
