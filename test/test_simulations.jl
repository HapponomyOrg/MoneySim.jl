using Test
using EconoSim
using MoneySim
using Agents
using FixedPointDecimals

@testset "wealth_distribution" begin
    num_actors = 10000

    model = create_econo_model(MonetaryActor{Currency, Balance{Currency}})

    sim_params = SimParams(MONTH)
    # The poorest Belgian groups have negative wealth; actors must allow negative balances to hold it.
    population_params = FixedPopulationParams(population = num_actors,
                                                create_actor! = m -> create_monetary_actor!(m, allow_negative_assets = true))

    monetary_params = FixedWealthParams(distribute_wealth! =
                                        m -> distribute_inequal!(m, MoneySim.get_wealth_inequality(BE, WS_MONEY_STOCK)))
    tax_scheme =
        StateTaxScheme(INCOME_TAX,
                        tax_recipients = num_actors,
                        get_tax_brackets = (_, p) -> MoneySim.calculate_flat_gdp_income_tax(BE, period = p),
                        get_projected_expenses = (_, _) -> 0,
                        deficit_spending = false,
                        debt_reduction = _ -> 0,
                        initial_income! =
                            a -> MoneySim.set_income!(a,
                                                        W_UNEQUAL,
                                                        MoneySim.get_gdp_per_capita(BE, period = MONTH),
                                                        MoneySim.overlap_adjusted_inequality_data(MoneySim.get_wealth_inequality(BE),
                                                                                            num_actors),
                                                        MoneySim.overlap_adjusted_inequality_data(MoneySim.get_income_inequality(BE,
                                                                                            period = MONTH, scale = IS_GDP),
                                                                                        num_actors)))

    MoneySim.initialize_simulation!(model,
                                    sim_params = sim_params,
                                    population_params = population_params,
                                    monetary_params = monetary_params,
                                    tax_scheme = tax_scheme)

    total_income = CUR_0

    for actor in allagents(model)
        total_income += actor.income
    end

    @test round(total_income) == round(MoneySim.get_gdp_per_capita(BE, period = MONTH) * num_actors)
end

# The testsets "Dem tax - SuMSy simulation", "Dem tax + VAT - SuMSy simulation" and "Income tax - SuMSy simulation"
# were dropped on 2026-11-11: their bodies were commented out and used FixedTaxScheme and IncomeTaxScheme, which are
# not brought back. test_tax_scheme.jl covers demurrage tax, VAT and income tax on StateTaxScheme.
