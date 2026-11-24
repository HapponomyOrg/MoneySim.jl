using Test
using MoneySimCore
using EconoSimCore

@testset "MoneySimCore" begin
    @testset "validation" begin
        @test validate_config(SimConfig()) == CONFIG_OK

        bad = SimConfig(periods = 0)
        @test validate_config(bad) == CONFIG_BAD_PERIODS

        bad = SimConfig(periods = 10, record_interval = 3)
        @test validate_config(bad) == CONFIG_BAD_RECORD_INTERVAL

        bad = SimConfig(population = PopulationConfig(count = 0))
        @test validate_config(bad) == CONFIG_BAD_POPULATION

        bad = SimConfig(wealth = WealthConfig(
            distribution = WealthDistribution.CUSTOM,
            custom = [money(1)]), population = PopulationConfig(count = 2))
        @test validate_config(bad) == CONFIG_BAD_WEALTH

        @test_throws ConfigError run_simulation(bad)
    end

    @testset "equal wealth, no dynamics" begin
        cfg = SimConfig(
            periods = 10,
            record_interval = 1,
            population = PopulationConfig(count = 10),
            wealth = WealthConfig(distribution = WealthDistribution.EQUAL,
                                  equal_amount = money(100)),
            money = MoneyConfig(model = MoneyModel.SUMSY,
                                interval = 10,
                                guaranteed_income = money(0),
                                demurrage = make_tiers(0.0)),
            transactions = TransactionConfig(enabled = false),
            tax = TaxConfig(kind = TaxKind.NONE))

        result = run_simulation(cfg)
        @test result.periods == 10
        @test result.mean[end] == 100.0
        @test result.total[end] == 1_000.0
        @test result.min[end] == 100.0
        @test result.max[end] == 100.0
        @test result.gini[end] == 0.0
        @test result.income_gini[end] == -1.0
        @test result.tax_collected[end] == 0.0

        base = (10 - 1) * 6
        @test result.shares[base + 3] == 0.5  # bottom 50%
        @test result.shares[base + 4] == 0.9  # bottom 90%
        @test result.shares[base + 6] == 1.0  # bottom 99.9%
    end

    @testset "SUMSY convergence" begin
        cfg = SimConfig(
            periods = 30_000,
            record_interval = 30,
            population = PopulationConfig(count = 100),
            wealth = WealthConfig(distribution = WealthDistribution.EQUAL,
                                  equal_amount = money(0)),
            money = MoneyConfig(model = MoneyModel.SUMSY,
                                interval = 30,
                                guaranteed_income = money(2_000),
                                demurrage = make_tiers(0.01)),
            transactions = TransactionConfig(enabled = false),
            tax = TaxConfig(kind = TaxKind.NONE))

        result = run_simulation(cfg)
        @test result.periods == 1_000
        @test isapprox(result.mean[end], 200_000.0; rtol = 1e-4)
        @test isapprox(result.total[end], 20_000_000.0; rtol = 1e-4)
        @test result.gini[end] == 0.0
    end

    @testset "income tax" begin
        state = SimState(3)
        state.wealth[1] = money(1_000)
        state.wealth[2] = money(1_000)
        state.wealth[3] = money(1_000)
        state.income[1] = money(1_000)
        state.income[2] = money(2_000)
        state.income[3] = money(5_000)

        brackets = [money(1_000), money(5_000), typemax(Money)]
        cfg = TaxConfig(kind = TaxKind.INCOME, interval = 1,
                        recipient = TaxRecipient.DESTROY,
                        brackets = brackets,
                        bracket_rates = Int64[100_000, 200_000, 300_000])

        collected = tax_step_income!(state, cfg, 1)
        @test collected == money(1_300)
        @test state.income == fill(zero(Money), 3)
        @test state.wealth[1] == money(900)
        @test state.wealth[2] == money(700)
        @test state.wealth[3] == money(100)
        @test state.tax_scale == 1.0

        state = SimState(3)
        state.wealth .= money(1_000)
        state.income[1] = money(1_000)
        state.income[2] = money(2_000)
        state.income[3] = money(5_000)
        cfg = TaxConfig(kind = TaxKind.INCOME, interval = 1,
                        recipient = TaxRecipient.DESTROY,
                        brackets = brackets,
                        bracket_rates = Int64[100_000, 200_000, 300_000],
                        target_revenue = money(650),
                        scale_to_target = true)
        collected = tax_step_income!(state, cfg, 1)
        @test collected == money(650)
        @test isapprox(state.tax_scale, 0.5; atol = 1e-9)

        state = SimState(3)
        state.wealth .= money(10_000)
        state.income[1] = money(1_000)
        state.income[2] = money(2_000)
        state.income[3] = money(5_000)
        cfg = TaxConfig(kind = TaxKind.INCOME, interval = 1,
                        recipient = TaxRecipient.DESTROY,
                        brackets = brackets,
                        bracket_rates = Int64[100_000, 200_000, 300_000],
                        target_revenue = money(1_950),
                        scale_to_target = true)
        collected = tax_step_income!(state, cfg, 1)
        @test collected == money(1_950)
        @test isapprox(state.tax_scale, 1.5; atol = 1e-9)
    end

    @testset "government deficit" begin
        state = SimState(10)
        state.wealth .= money(1_000)
        tax = TaxConfig(kind = TaxKind.NONE)

        government = GovernmentConfig(enabled = true,
                                      expenses = money(1_500),
                                      deficit_spending = true)
        government_step!(state, government, tax, MONEY_ZERO)
        @test state.government_debt == money(1_500)
        @test total_wealth(state) == money(11_500)

        state = SimState(10)
        state.wealth .= money(1_000)
        government = GovernmentConfig(enabled = true,
                                      expenses = money(1_500),
                                      deficit_spending = false)
        government_step!(state, government, tax, money(1_000))
        @test state.government_debt == MONEY_ZERO
        @test total_wealth(state) == money(10_000)
    end

    @testset "yard sale conserves money" begin
        cfg = SimConfig(
            periods = 100,
            record_interval = 10,
            population = PopulationConfig(count = 50),
            wealth = WealthConfig(distribution = WealthDistribution.EQUAL,
                                  equal_amount = money(1_000)),
            money = MoneyConfig(model = MoneyModel.SUMSY,
                                interval = 1,
                                guaranteed_income = money(0),
                                demurrage = make_tiers(0.0)),
            transactions = TransactionConfig(enabled = true,
                                             transactions_per_step = 200,
                                             transfer_rate = 0.2,
                                             wealth_advantage = 0.2),
            tax = TaxConfig(kind = TaxKind.NONE))

        result = run_simulation(cfg)
        @test result.periods == 10
        @test isapprox(result.total[end], 50_000.0; rtol = 1e-9)
        @test result.gini[end] > 0.0
        @test result.income_gini[1] >= 0.0
    end

    @testset "demographics" begin
        function run_state(population; periods = 1)
            cfg = SimConfig(
                periods = periods,
                population = population,
                wealth = WealthConfig(distribution = WealthDistribution.EQUAL,
                                      equal_amount = money(100)),
                money = MoneyConfig(model = MoneyModel.SUMSY, interval = 1,
                                    guaranteed_income = money(0),
                                    demurrage = make_tiers(0.0)),
                transactions = TransactionConfig(enabled = false))
            state = SimState(population.count)
            results = ResultBuffers(periods)
            run_simulation!(cfg, state, results)
            return state, results
        end

        births, birth_results = run_state(PopulationConfig(
            count = 10, birth_rate = 0.1, birth_wealth = money(50), typed_gi = true))
        @test births.n == 11
        @test alive_count(births) == 11
        @test births.wealth[11] == money(50)
        @test birth_results.total[end] == 1_050.0

        deaths, death_results = run_state(PopulationConfig(count = 10, death_rate = 0.1))
        @test alive_count(deaths) == 9
        @test death_results.total[end] == 900.0

        aged, _ = run_state(PopulationConfig(
            count = 10, aging_interval = 1, aging_rate = 1.0,
            typed_gi = true, gi_child = false, gi_adult = true, gi_elder = true))
        @test all(==(UInt8(1)), aged.age_type)
        @test all(==(UInt8(1)), aged.gi_eligible)
    end

    @testset "adaptations" begin
        injected = run_simulation(SimConfig(
            periods = 1,
            population = PopulationConfig(count = 10),
            wealth = WealthConfig(distribution = WealthDistribution.EQUAL,
                                  equal_amount = money(100)),
            money = MoneyConfig(model = MoneyModel.SUMSY, interval = 1,
                                guaranteed_income = money(0),
                                demurrage = make_tiers(0.0)),
            transactions = TransactionConfig(enabled = false),
            adaptations = AdaptationConfig(inject_enabled = true,
                                           inject_amount = money(1_000),
                                           inject_interval = 1)))
        @test injected.total[end] == 2_000.0

        destroyed = run_simulation(SimConfig(
            periods = 1,
            population = PopulationConfig(count = 10),
            wealth = WealthConfig(distribution = WealthDistribution.EQUAL,
                                  equal_amount = money(1_000)),
            money = MoneyConfig(model = MoneyModel.SUMSY, interval = 1,
                                guaranteed_income = money(0),
                                demurrage = make_tiers(0.0)),
            transactions = TransactionConfig(enabled = false),
            adaptations = AdaptationConfig(destroy_enabled = true,
                                           destroy_amount = money(1_000),
                                           destroy_interval = 1)))
        @test destroyed.total[end] == 9_000.0
    end

    @testset "GDP volume target" begin
        cfg = SimConfig(
            periods = 1,
            population = PopulationConfig(count = 10),
            wealth = WealthConfig(distribution = WealthDistribution.EQUAL,
                                  equal_amount = money(1_000)),
            money = MoneyConfig(model = MoneyModel.SUMSY, interval = 1,
                                guaranteed_income = money(0),
                                demurrage = make_tiers(0.0)),
            transactions = TransactionConfig(enabled = false,
                                             transfer_rate = 0.2),
            gdp = GdpConfig(enabled = true, per_capita = money(50)))

        state = SimState(cfg.population.count)
        results = ResultBuffers(1)
        run_simulation!(cfg, state, results)
        @test sum(state.income) + sum(state.step_income) >= money(500)
        @test total_wealth(state) == money(10_000)
    end

    @testset "wealth tax" begin
        function tax_result(kind; actor = 0)
            cfg = SimConfig(
                periods = 1,
                record_interval = 1,
                population = PopulationConfig(count = 10),
                wealth = WealthConfig(distribution = WealthDistribution.EQUAL,
                                      equal_amount = money(1_000)),
                money = MoneyConfig(model = MoneyModel.SUMSY,
                                    interval = 1,
                                    guaranteed_income = money(0),
                                    demurrage = make_tiers(0.0)),
                transactions = TransactionConfig(enabled = false),
                tax = TaxConfig(kind = TaxKind.WEALTH, rate = 0.10, interval = 1,
                                recipient = kind, recipient_actor = actor))
            return run_simulation(cfg)
        end

        everyone = tax_result(TaxRecipient.EVERYONE)
        @test everyone.tax_collected[end] == 1_000.0
        @test isapprox(everyone.total[end], 10_000.0; rtol = 1e-9)
        @test everyone.gini[end] == 0.0

        destroy = tax_result(TaxRecipient.DESTROY)
        @test destroy.tax_collected[end] == 1_000.0
        @test isapprox(destroy.total[end], 9_000.0; rtol = 1e-9)

        one = tax_result(TaxRecipient.ONE_ACTOR; actor = 1)
        @test isapprox(one.total[end], 10_000.0; rtol = 1e-9)
        @test one.gini[end] > 0.0

        first_n = tax_result(TaxRecipient.FIRST_N; actor = 2)
        @test isapprox(first_n.total[end], 10_000.0; rtol = 1e-9)
        @test first_n.gini[end] > 0.0
    end

    @testset "custom and concentrated wealth" begin
        custom = run_simulation(SimConfig(
            periods = 1,
            population = PopulationConfig(count = 3),
            wealth = WealthConfig(distribution = WealthDistribution.CUSTOM,
                                  custom = [money(100), money(200), money(300)]),
            money = MoneyConfig(model = MoneyModel.SUMSY, interval = 1,
                                guaranteed_income = money(0),
                                demurrage = make_tiers(0.0)),
            transactions = TransactionConfig(enabled = false),
            tax = TaxConfig(kind = TaxKind.NONE)))
        @test custom.total[end] == 600.0
        @test custom.min[end] == 100.0
        @test custom.max[end] == 300.0

        concentrated = run_simulation(SimConfig(
            periods = 1,
            population = PopulationConfig(count = 10),
            wealth = WealthConfig(distribution = WealthDistribution.CONCENTRATED,
                                  equal_amount = money(100)),
            money = MoneyConfig(model = MoneyModel.SUMSY, interval = 1,
                                guaranteed_income = money(0),
                                demurrage = make_tiers(0.0)),
            transactions = TransactionConfig(enabled = false),
            tax = TaxConfig(kind = TaxKind.NONE)))
        @test concentrated.total[end] == 1_000.0
        @test isapprox(concentrated.gini[end], 0.9; atol = 1e-9)
    end

    @testset "bank" begin
        cfg = SimConfig(
            periods = 1,
            population = PopulationConfig(count = 10),
            wealth = WealthConfig(distribution = WealthDistribution.EQUAL,
                                  equal_amount = money(1_000)),
            money = MoneyConfig(model = MoneyModel.DEBT_BASED, interval = 1,
                                guaranteed_income = money(0),
                                demurrage = make_tiers(0.0), interest_rate = 0),
            transactions = TransactionConfig(enabled = false),
            bank = BankConfig(enabled = true, actor_index = 1,
                              lending_amount = money(1_000),
                              lending_targets = 2))
        state = SimState(10)
        results = ResultBuffers(1)
        run_simulation!(cfg, state, results)
        @test state.wealth[2] == money(1_500)
        @test state.wealth[3] == money(1_500)
        @test state.debt[2] == money(500)
        @test state.debt[3] == money(500)
        @test total_wealth(state) == money(11_000)

        state = SimState(2)
        state.wealth .= money(1_000)
        state.debt[2] = money(1_000)
        money_cfg = MoneyConfig(model = MoneyModel.DEBT_BASED, interval = 1,
                                interest_rate = ppm(0.01))
        bank = BankConfig(enabled = true, actor_index = 1)
        bank_step!(state, money_cfg, bank)
        @test state.wealth[1] == money(1_010)
        @test state.wealth[2] == money(990)

        state = SimState(2)
        state.wealth .= money(1_000)
        state.debt[2] = money(1_000)
        bank = BankConfig(enabled = true, actor_index = 1,
                          repayment_rate = 0.1)
        repay_cfg = MoneyConfig(model = MoneyModel.DEBT_BASED, interval = 1,
                                interest_rate = 0)
        bank_step!(state, repay_cfg, bank)
        @test state.wealth[2] == money(900)
        @test state.debt[2] == money(900)
    end

    @testset "loan circuit" begin
        # Growth mode: each balance accrues g; p is converted to bank reserves.
        growth_cfg = SimConfig(
            periods = 1,
            population = PopulationConfig(count = 2),
            wealth = WealthConfig(distribution = WealthDistribution.EQUAL,
                                  equal_amount = money(1_000)),
            money = MoneyConfig(model = MoneyModel.LOAN_CIRCUIT, interval = 1,
                                interest_rate = ppm(0.10)),
            transactions = TransactionConfig(enabled = false),
            loan_circuit = LoanCircuitConfig(enabled = true,
                                             profit_rate = 0.05,
                                             maturity = 1, mode = 0))
        state = SimState(2)
        results = ResultBuffers(1)
        run_simulation!(growth_cfg, state, results)
        @test state.wealth[1] == money(1_100)
        @test state.wealth[2] == money(1_100)
        @test state.debt[1] == money(1_150)
        @test state.bank_reserve == money(100)
        @test total_wealth(state) == money(2_200)

        # Loan-rate mode: one cycle should grow the pool by the paper's formula.
        function loan_cfg(periods, profit; seed = 42)
            SimConfig(
                periods = periods,
                seed = seed,
                population = PopulationConfig(count = 100),
                wealth = WealthConfig(distribution = WealthDistribution.EQUAL,
                                      equal_amount = money(100)),
                money = MoneyConfig(model = MoneyModel.LOAN_CIRCUIT, interval = 1,
                                    interest_rate = ppm(0.15)),
                transactions = TransactionConfig(enabled = true,
                                                 transactions_per_step = 2_000,
                                                 transfer_rate = 0.2,
                                                 wealth_advantage = 0.0),
                loan_circuit = LoanCircuitConfig(enabled = true,
                                                 profit_rate = profit,
                                                 maturity = 20, mode = 1))
        end

        one = run_simulation(loan_cfg(1, 0.008))
        @test isapprox(one.total[1], 11_082.35; atol = 0.01)

        stable = run_simulation(loan_cfg(500, 0.008))
        @test stable.periods == 500
        @test isapprox(stable.total[end], 720_271_164_192_546.0; rtol = 1e-9)

        collapsed = run_simulation(loan_cfg(500, 0.009))
        @test collapsed.periods == 193
        @test isapprox(collapsed.total[end], 842_970.5606; rtol = 1e-9)
    end

    @testset "countries" begin
        be = belgium()
        @test population_total(be) == 11_697_556
        @test money_per_capita(be) == div(be.money_stock, 11_697_556)
        @test gdp_per_capita(be) == div(be.government.gdp, 11_697_556)

        # The Belgian schedule starts with a 0% band up to 10,190.
        @test be.government.tax_rates == Int64[0, 250_000, 400_000, 450_000, 500_000]
        brackets = vcat(be.government.tax_brackets, [typemax(Money)])
        @test bracket_tax(money(10_190), brackets,
                          be.government.tax_rates) == MONEY_ZERO
        @test bracket_tax(money(10_200), brackets,
                          be.government.tax_rates) == money(2.5)

        values = unequal_wealth(be, 1_000)
        @test length(values) == 1_000
        @test maximum(values) > minimum(values)
        # Bottom overlap adjustment lifts bottom_10 above the raw negative value.
        @test values[11] > MONEY_ZERO
        @test isapprox(currency(sum(values)),
                       currency(money_per_capita(be)) * 1_000; rtol = 1e-6)

        cfg = country_config(be; actors = 200, periods = 12,
                             wealth_distribution = WealthDistribution.CUSTOM,
                             tax_kind = TaxKind.NONE,
                             government_enabled = false,
                             record_interval = 12)
        result = run_simulation(cfg)
        @test result.periods == 1
        @test isfinite(result.gini[1])
        @test result.total[1] > 0

        # Paper-3 direction checks at a 1,000-actor sample.
        a1 = country_config(be; actors = 1_000, periods = 120,
                            wealth_distribution = WealthDistribution.CUSTOM,
                            tax_kind = TaxKind.NONE,
                            government_enabled = false,
                            record_interval = 12)
        r1 = run_simulation(a1)
        @test 0.40 < r1.gini[end] < 0.50
        @test isapprox(r1.mean[end], currency(money_per_capita(be)); rtol = 0.01)

        target = div((be.government.expenses - be.government.interest_cost) * 12 * 1_000,
                     population_total(be))
        a3 = country_config(be; actors = 1_000, periods = 120,
                            wealth_distribution = WealthDistribution.CUSTOM,
                            tax_kind = TaxKind.INCOME, tax_interval = 12,
                            target_revenue = target,
                            government_enabled = false,
                            record_interval = 12)
        r3 = run_simulation(a3)
        @test r3.tax_collected[end] > 0
        @test r3.gini[end] < r1.gini[end]
    end

    @testset "determinism" begin
        function noisy(seed)
            cfg = SimConfig(
                periods = 50,
                record_interval = 5,
                seed = seed,
                population = PopulationConfig(count = 30),
                wealth = WealthConfig(distribution = WealthDistribution.EQUAL,
                                      equal_amount = money(1_000)),
                money = MoneyConfig(model = MoneyModel.SUMSY, interval = 1,
                                    guaranteed_income = money(0),
                                    demurrage = make_tiers(0.0)),
                transactions = TransactionConfig(enabled = true,
                                                 transactions_per_step = 50,
                                                 transfer_rate = 0.2),
                tax = TaxConfig(kind = TaxKind.NONE))
            return run_simulation(cfg).gini
        end

        @test noisy(7) == noisy(7)
        @test noisy(7) != noisy(8)
    end

    @testset "demurrage tax" begin
        state = SimState(3)
        state.wealth[1] = money(1_000)
        state.wealth[2] = money(2_000)
        state.wealth[3] = money(5_000)
        cfg = TaxConfig(kind = TaxKind.DEMURRAGE, interval = 1,
                        recipient = TaxRecipient.DESTROY,
                        brackets = [money(1_000), money(5_000), typemax(Money)],
                        bracket_rates = Int64[100_000, 200_000, 300_000])
        collected = tax_step_demurrage!(state, cfg, MoneyConfig(), 1)
        @test collected == money(1_300)
        @test state.wealth == [money(900), money(1_700), money(4_100)]

        state = SimState(2)
        state.wealth[1] = money(1_000)
        state.wealth[2] = money(600)
        money_cfg = MoneyConfig(demurrage_free = money(500))
        flat = TaxConfig(kind = TaxKind.DEMURRAGE, interval = 1,
                         recipient = TaxRecipient.DESTROY,
                         brackets = [typemax(Money)],
                         bracket_rates = Int64[ppm(0.10)])
        collected = tax_step_demurrage!(state, flat, money_cfg, 1)
        @test collected == money(60)
        @test state.wealth == [money(950), money(590)]
    end

    @testset "VAT" begin
        state = SimState(3)
        state.wealth .= money(1_000)
        for i in 1:3
            state.vat_eligible[i] = money(1_000)
        end
        vat = VatConfig(enabled = true, rate = 0.10, interval = 1,
                        recipient = TaxRecipient.DESTROY)
        collected = vat_step!(state, vat, TaxConfig(kind = TaxKind.NONE), 1)
        @test isapprox(currency(collected), 272.7273; atol = 1e-3)
        @test isapprox(currency(state.wealth[1]), 909.0909; atol = 1e-3)
        @test all(iszero, state.vat_eligible)

        state = SimState(1)
        state.wealth[1] = money(1_000)
        state.vat_eligible[1] = money(1_000)
        deduct = VatConfig(enabled = true, rate = 0.10, interval = 1,
                           deduct_from_taxes = true,
                           recipient = TaxRecipient.DESTROY)
        vat_step!(state, deduct, TaxConfig(kind = TaxKind.NONE), 1)
        @test state.vat_deduction[1] == money(90.9091)

        # Projected income is part of the first VAT window, matching legacy
        # `init_income!`.
        notional_cfg = SimConfig(
            periods = 1,
            population = PopulationConfig(count = 2),
            tax = TaxConfig(kind = TaxKind.NONE,
                            notional = [money(100), money(200)]))
        notional_state = SimState(2)
        reset_state!(notional_state, notional_cfg)
        @test notional_state.vat_eligible == [money(100), money(200)]

        income_tax = TaxConfig(kind = TaxKind.INCOME, interval = 1,
                               recipient = TaxRecipient.DESTROY,
                               brackets = [typemax(Money)],
                               bracket_rates = Int64[ppm(0.20)])
        state.income[1] = money(1_000)
        collected = tax_step_income!(state, income_tax, 1)
        @test isapprox(currency(collected), 109.0909; atol = 1e-3)
        @test state.vat_deduction[1] == MONEY_ZERO
    end

    @testset "fixed money model" begin
        cfg = SimConfig(
            periods = 10,
            population = PopulationConfig(count = 10),
            wealth = WealthConfig(distribution = WealthDistribution.EQUAL,
                                  equal_amount = money(100)),
            money = MoneyConfig(model = MoneyModel.FIXED, interval = 1),
            transactions = TransactionConfig(enabled = false),
            tax = TaxConfig(kind = TaxKind.NONE))
        result = run_simulation(cfg)
        @test result.total[end] == 1_000.0
        @test result.mean[end] == 100.0
    end

    @testset "typed SuMSy by age" begin
        cfg = SimConfig(
            periods = 1,
            population = PopulationConfig(count = 3,
                                          age_shares = Int64[3_334, 3_333, 3_333]),
            wealth = WealthConfig(distribution = WealthDistribution.EQUAL,
                                  equal_amount = money(0)),
            money = MoneyConfig(model = MoneyModel.SUMSY, interval = 1,
                                guaranteed_income = money(0),
                                demurrage = make_tiers(0.0),
                                typed_guaranteed_income =
                                    [money(100), money(200), money(300)]),
            transactions = TransactionConfig(enabled = false))
        state = SimState(3)
        results = ResultBuffers(1)
        run_simulation!(cfg, state, results)
        @test state.age_type == UInt8[0, 1, 2]
        @test state.wealth == [money(100), money(200), money(300)]
    end

    @testset "paper 2 — SUMSY equilibria" begin
        tiers = [(0.0, 0.01), (50_000.0, 0.02), (500_000.0, 0.05),
                 (1_000_000.0, 0.10), (10_000_000.0, 0.50),
                 (50_000_000.0, 0.95)]

        function sumsy_run(; eligible = 100, noneligible = 0,
                           transactions = 200, periods = 4_500,
                           demurrage = make_tiers(0.01), equal = false)
            n = eligible + noneligible
            base = telo(money(2_000), demurrage)
            initial = noneligible > 0 ? div(base * eligible, n) : base
            eligible_flags = Vector{UInt8}(undef, n)
            for i in 1:n
                eligible_flags[i] = i <= eligible ? UInt8(1) : UInt8(0)
            end
            cfg = SimConfig(
                periods = periods,
                record_interval = 30,
                population = PopulationConfig(count = n,
                                              gi_eligible = eligible_flags),
                wealth = WealthConfig(distribution = WealthDistribution.EQUAL,
                                      equal_amount = initial),
                money = MoneyConfig(model = MoneyModel.SUMSY, interval = 30,
                                    guaranteed_income = money(2_000),
                                    demurrage = demurrage),
                transactions = TransactionConfig(enabled = transactions > 0,
                                                 transactions_per_step = transactions,
                                                 transfer_rate = 0.2),
                adaptations = AdaptationConfig(equal_distribution = equal,
                                               equal_interval = 30),
                tax = TaxConfig(kind = TaxKind.NONE))
            return run_simulation(cfg).total[end]
        end

        @test isapprox(sumsy_run(), 20_000_000.0; rtol = 0.01)
        @test isapprox(sumsy_run(noneligible = 25), 20_000_000.0; rtol = 0.01)

        tiered = make_tiers(tiers)
        e2 = sumsy_run(demurrage = tiered)
        @test currency(telo(money(2_000) * 100, tiered)) * 0.99 <= e2
        @test e2 <= currency(telo(money(2_000), tiered) * 100) * 1.01

        e3 = sumsy_run(noneligible = 25, transactions = 0,
                       demurrage = tiered, equal = true)
        lower = currency(telo(money(2_000) * 100, tiered))
        upper = currency(telo(div(money(2_000) * 100, 125), tiered) * 125)
        @test lower * 0.99 <= e3 <= upper * 1.01

        e5 = sumsy_run(noneligible = 25, demurrage = tiered)
        @test lower * 0.99 <= e5 <= upper * 1.01
    end

    @testset "paper 2 — transactional demurrage" begin
        n = 100
        cfg = SimConfig(
            periods = 4_500,
            record_interval = 30,
            population = PopulationConfig(count = n,
                                          gi_eligible = fill(UInt8(1), n)),
            wealth = WealthConfig(distribution = WealthDistribution.EQUAL,
                                  equal_amount = money(200_000)),
            money = MoneyConfig(model = MoneyModel.SUMSY, interval = 30,
                                guaranteed_income = money(2_000),
                                demurrage = make_tiers(0.01),
                                transactional = true),
            transactions = TransactionConfig(enabled = true,
                                             transactions_per_step = 200,
                                             transfer_rate = 0.2),
            tax = TaxConfig(kind = TaxKind.NONE))
        result = run_simulation(cfg)
        @test all(isfinite, result.total)
        @test all(>(0.0), result.total)
        @test maximum(result.total) <= 20_000_000.0 * 1.01
    end

    @testset "paper 2 — consumer–supplier" begin
        function consumer_supplier(consumers, demand, price, demurrage)
            n = 1 + consumers
            initial = telo(money(2_000), demurrage)
            custom = Vector{Money}(undef, n)
            custom[1] = MONEY_ZERO
            for i in 2:n
                custom[i] = initial
            end
            cfg = SimConfig(
                periods = 45_000,
                record_interval = 1_500,
                population = PopulationConfig(count = n),
                wealth = WealthConfig(distribution = WealthDistribution.CUSTOM,
                                      custom = custom),
                money = MoneyConfig(model = MoneyModel.SUMSY, interval = 30,
                                    guaranteed_income = money(2_000),
                                    demurrage = demurrage),
                transactions = TransactionConfig(
                    enabled = true, model = TransactionModel.CONSUMER_SUPPLIER,
                    suppliers = 1, consumers_per_supplier = consumers,
                    demand = demand, price = money(price)),
                tax = TaxConfig(kind = TaxKind.NONE))
            state = SimState(n)
            results = ResultBuffers(30)
            run_simulation!(cfg, state, results)
            return currency(state.wealth[1])
        end

        flat = make_tiers(0.01)
        @test isapprox(consumer_supplier(50, 5, 1, flat), 742_354.42; rtol = 1e-3)
        @test isapprox(consumer_supplier(100, 5, 1, flat), 1_484_708.83; rtol = 1e-3)
        @test isapprox(consumer_supplier(100, 3, 2, flat), 1_781_650.60; rtol = 1e-3)

        tiered = make_tiers([(0.0, 0.01), (50_000.0, 0.02),
                             (500_000.0, 0.05), (1_000_000.0, 0.10),
                             (10_000_000.0, 0.50), (50_000_000.0, 0.95)])
        @test isapprox(consumer_supplier(50, 5, 1, tiered), 392_749.90; rtol = 1e-3)
        @test isapprox(consumer_supplier(100, 5, 1, tiered), 595_500.00; rtol = 1e-3)
        @test isapprox(consumer_supplier(100, 3, 2, tiered), 652_600.00; rtol = 1e-3)
    end

    @testset "paper 1 — random loan circuit" begin
        set_overflow_mode!(OVERFLOW_SATURATE)
        growth = SimConfig(
            periods = 500,
            seed = 7,
            population = PopulationConfig(count = 100),
            wealth = WealthConfig(distribution = WealthDistribution.EQUAL,
                                  equal_amount = money(10_000)),
            money = MoneyConfig(model = MoneyModel.LOAN_CIRCUIT, interval = 1,
                                interest_rate = ppm(0.05)),
            transactions = TransactionConfig(enabled = true,
                                             transactions_per_step = 2_000,
                                             transfer_rate = 0.2),
            loan_circuit = LoanCircuitConfig(
                enabled = true, mode = 0, maturity = 20,
                random_mode = LoanRandomMode.GROWTH,
                min_value = 0.02, max_value = 0.12,
                relative_profit = 0.0, no_loss = true))
        result = run_simulation(growth)
        @test result.periods == 500
        @test all(isfinite, result.total)
        @test all(isfinite, result.growth_ratio)
        @test result.total[end] > 0.0

        loan_rate = SimConfig(
            periods = 500,
            seed = 11,
            population = PopulationConfig(count = 100),
            wealth = WealthConfig(distribution = WealthDistribution.EQUAL,
                                  equal_amount = money(10_000)),
            money = MoneyConfig(model = MoneyModel.LOAN_CIRCUIT, interval = 1,
                                interest_rate = ppm(0.15)),
            transactions = TransactionConfig(enabled = true,
                                             transactions_per_step = 2_000,
                                             transfer_rate = 0.2),
            loan_circuit = LoanCircuitConfig(
                enabled = true, mode = 1, profit_rate = 0.008, maturity = 20,
                random_mode = LoanRandomMode.LOAN_RATE,
                min_value = 0.10, max_value = 0.20,
                min_maturity = 10, max_maturity = 30,
                relative_profit = 0.008, no_loss = true))
        result = run_simulation(loan_rate)
        @test 0 < result.periods <= 500
        @test all(isfinite, result.total)
        @test all(isfinite, result.loan_debt)
        set_overflow_mode!(OVERFLOW_ERROR)
    end
end
