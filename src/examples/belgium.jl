using EconoSim
using MoneySim
using DataFrames
using Agents

set_currency_precision!(4)

M2 = Currency(639000000000)
# Average of year 2023
# Source: https://tradingeconomics.com/belgium/money-supply-m2

INCOME_TAX_BRACKETS = [(0.1, 0.25), (15200, 0.4), (26830, 0.45), (46440, 0.5)]
# Source https://financien.belgium.be/nl/particulieren/belastingaangifte/belastingtarieven-inkomen/belastingtarieven#q1

POP_MIN_18 = 1314555 + 274738 + 747040
POP_18_TO_64 = 4029828 + 804889 + 2215697
POP_65_PLUS = 1430423 + 161548 + 718838
POPULATION = POP_MIN_18 + POP_18_TO_64 + POP_65_PLUS
# Source: https://bestat.statbel.fgov.be/bestat/crosstable.xhtml?view=161080d2-d411-4e40-9a0f-a27db5e2b6e1

PERCENT_MIN_18 = POP_MIN_18 / POPULATION
PERCENT_18_TO_64 = POP_18_TO_64 / POPULATION
PERCENT_65_PLUS = POP_65_PLUS / POPULATION

M2_PER_CAPITA = M2 / POPULATION

GDP_PER_CAPITA = 49791 # GDP per capita for Belgium in 2023.

VAT_PER_CAPITA = 37083000000 / POPULATION # Total for 2023
# Source https://stat.nbb.be/Index.aspx?DataSetCode=TREASREV&lang=nl

VAT = VAT_PER_CAPITA / GDP_PER_CAPITA # Average VAT rate

EXPENSES_PER_CAPITA = 319141000000 / POPULATION
# Source: https://www.nbb.be/doc/dq/n/dq3/histo/nnco23.pdf

INTEREST_COST_PER_CAPITA = 11818000000 / POPULATION
# Source: https://www.nbb.be/doc/dq/n/dq3/histo/nnco23.pdf

PENSION_COST = 62900000000
PENSION_COST_PER_CAPITA = PENSION_COST / POPULATION
# Source: https://www.ccrek.be/sites/default/files/Docs/181e_b_II_SocZk.pdf

UNEMPLOYMENT_COST_PER_CAPITA = 6400000000 / POPULATION
# Source: https://www.ccrek.be/sites/default/files/Docs/181e_b_II_SocZk.pdf

NET_MONTHLY_EXPENSES_PER_CAPITA = (EXPENSES_PER_CAPITA - INTEREST_COST_PER_CAPITA - PENSION_COST_PER_CAPITA - UNEMPLOYMENT_COST_PER_CAPITA) / 12

AVG_MONTHLY_PENSION = PENSION_COST / POP_65_PLUS / 12

GI_MIN_18 = 2000 # 500
GI_18_TO_64 = 2000
GI_65_PLUS = 2000 # AVG_MONTHLY_PENSION

D_MIN_18 = GI_MIN_18 / M2_PER_CAPITA
D_18_TO_64 = GI_18_TO_64 / M2_PER_CAPITA
D_65_PLUS = GI_65_PLUS / M2_PER_CAPITA

D = 2000 / M2_PER_CAPITA

DEMOGRAPHIC_DEM = D_MIN_18 * PERCENT_MIN_18 + D_18_TO_64 * PERCENT_18_TO_64 + D_65_PLUS * PERCENT_65_PLUS

DEM_TAX = NET_MONTHLY_EXPENSES_PER_CAPITA / M2_PER_CAPITA

INEQUALITY_DATA = InequalityData(9347930,     # Top 0.1%
                                3988639.8,    # Top 1%
                                1388465.6,    # Top 10%
                                266649.9,     # High middle 40%
                                51125.0871,   # Low middle 40%
                                -709.6,       # Bottom 10%
                                -44162.4,     # Bottom 1%
                                nothing,      # Bottom 0.1% - not applicable
                                money_per_head = M2_PER_CAPITA)

MONTH = 1
YEAR = 12

NUM_ACTORS = 5000

age_typed_population = Dict(:pop_min_18 => PERCENT_MIN_18,
                                :pop_18_to_64 => PERCENT_18_TO_64,
                                :pop_65_plus => PERCENT_65_PLUS)
    
basic_sumsy_groups = Dict{Symbol, Tuple{Real, Real}}(:pop_min_18 => (GI_MIN_18, 0),
                                                    :pop_18_to_64 => (GI_18_TO_64, 0),
                                                    :pop_65_plus => (AVG_MONTHLY_PENSION, 0))

function post_process_sim_data!(actor_data, model_data)
    rename!(actor_data,
            3 => :deposit,
            4 => :equity,
            5 => :wealth,
            6 => :income,
            7 => :expenses,
            8 => :paid_tax,
            9 => :paid_vat)

    rename!(model_data,
            2 => :num_actors,
            3 => :gdp,
            4 => :transactions,
            5 => :min_transaction,
            6 => :max_transaction,
            7 => :collected_tax,
            8 => :failed_tax,
            9 => :collected_vat,
            10 => :failed_vat)

    return actor_data, model_data
end

function simulate_belgium(;sim_length::Int = 15 * YEAR,
                        num_actors::Int = NUM_ACTORS,
                        population_types = age_typed_population,
                        adjust_pop_up::Symbol = :pop_65_plus,
                        adjust_pop_down::Symbol = :pop_min_18,
                        allow_negative_balances::Bool = true,
                        demurrage::DemSettings = DEMOGRAPHIC_DEM,
                        gdp_scaling::Real = 1.0,
                        wealth_transfer::Real = 0.2,
                        sumsy_groups::Dict{Symbol, Tuple{Real, Real}} = basic_sumsy_groups,
                        inequality_data::InequalityData = INEQUALITY_DATA,
                        tax_type::TAX_TYPE = DEMURRAGE_TAX,
                        tax_brackets::DemSettings = DEM_TAX,
                        tax_recipients::Real = 1)
    model = create_sumsy_model(MONTH, model_behaviors = process_model_sumsy!)
    dummy_sumsy = SuMSy(2000, 0, DEMOGRAPHIC_DEM)

    sim_params = SimParams(sim_length)
    population_params = TypedPopulationParams(num_actors = num_actors,
                                                actor_types = population_types,
                                                adjust_up = adjust_pop_up,
                                                adjust_down = adjust_pop_down,
                                                create_actor! = m -> create_sumsy_actor(m,
                                                                                        sumsy = dummy_sumsy,
                                                                                        sumsy_interval = MONTH,
                                                                                        allow_negatives = allow_negative_balances))
    behaviour_params = GDPYardSaleParams(gdp_period = YEAR,
                                            gdp_per_capita = GDP_PER_CAPITA * gdp_scaling,
                                            wealth_transfer_range = wealth_transfer:wealth_transfer:wealth_transfer,
                                            minimal_wealth_transfer = 0,
                                            remove_broke_actors = false,
                                            gdp_model_behavior = gdp_yard_sale!)
    monetary_params = StandardSuMSyParams(sumsy_interval = MONTH,
                                            transactional = false,
                                            configure_sumsy_actors! = m -> type_based_sumsy_actors!(m, sumsy_groups, demurrage),
                                            distribute_wealth! = m -> typed_inequal_wealth_distribution!(m,
                                                                                                        inequality_data,
                                                                                                        collect(keys(population_types))))
    tax_scheme = FixedTaxScheme(tax_type,
                                tax_recipients = round(num_actors * tax_recipients),
                                tax_interval = YEAR,
                                tax_brackets = tax_brackets,
                                tax_free = 0,
                                vat_interval = 3 * MONTH,
                                vat = VAT)
    data_handler = IntervalDataHandler(interval = YEAR,
                                        actor_data_collectors = [deposit_collector,
                                                                equity_collector,
                                                                wealth_collector,
                                                                income_collector!,
                                                                expenses_collector!,
                                                                paid_tax_collector!,
                                                                paid_vat_collector!,
                                                                :types],
                                        model_data_collectors = [nagents,
                                                                gdp_collector!,
                                                                transactions_collector!,
                                                                min_transaction_collector!,
                                                                max_transaction_collector!,
                                                                tax_collector!,
                                                                failed_tax_collector!,
                                                                vat_collector!,
                                                                failed_vat_collector!],
                                        post_processing! = post_process_sim_data!)

    run_simulation(model,
                    sim_params = sim_params,
                    population_params = population_params,
                    behaviour_params = behaviour_params,
                    monetary_params = monetary_params,
                    tax_scheme = tax_scheme,
                    data_handler = data_handler)
end