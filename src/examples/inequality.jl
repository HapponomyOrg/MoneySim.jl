using EconoSim
using MoneySim
using DataFrames
using Agents

set_currency_precision!(4)

const M2 = Currency(639000000000)
# Average of year 2023
# Source: https://tradingeconomics.com/belgium/money-supply-m2

const AVG_INCOME = 4318
# Source: https://www.jobat.be/nl/art/belg-verdient-gemiddeld-4318-euro#:~:text=1%20van%20895-,Belg%20verdient%20gemiddeld%204.318%20euro,die%20worden%20steeds%20beter%20beloond.

const AVG_COST_OF_LIVING = 927.80
# Source = https://werelddata.nl/kosten-van-levensonderhoud/belgie#:~:text=In%20het%20kort,5.1%25%20lager%20dan%20in%20Nederland.

const AVG_RENT = 1007
# Source: https://www.livios.be/nl/artikel/100605/problemen-op-de-huurmarkt-stijgende-huurprijzen-en-tekort-aan-huurwoningen/#:~:text=Huren%20is%20er%20ook%20niet,gemiddeld%20841%20euro%20per%20maand.

const INCOME_TAX_BRACKETS = [(0.1, 0.25), (15200, 0.4), (26830, 0.45), (46440, 0.5)]
# Source https://financien.belgium.be/nl/particulieren/belastingaangifte/belastingtarieven-inkomen/belastingtarieven#q1

const POP_MIN_18 = 1314555 + 274738 + 747040
const POP_18_TO_64 = 4029828 + 804889 + 2215697
const POP_65_PLUS = 1430423 + 161548 + 718838
const POPULATION = POP_MIN_18 + POP_18_TO_64 + POP_65_PLUS
# Source: https://bestat.statbel.fgov.be/bestat/crosstable.xhtml?view=161080d2-d411-4e40-9a0f-a27db5e2b6e1

const PERCENT_MIN_18 = POP_MIN_18 / POPULATION
const PERCENT_18_TO_64 = POP_18_TO_64 / POPULATION
const PERCENT_65_PLUS = POP_65_PLUS / POPULATION

const M2_PER_CAPITA = M2 / POPULATION

const AVG_GROSS_MONTHLY_INCOME = 4076
const AVG_GROSS_YEARLY_INCOME = AVG_GROSS_MONTHLY_INCOME * 12
# Source: https://statbel.fgov.be/nl/themas/werk-opleiding/lonen-en-arbeidskosten/gemiddelde-bruto-maandlonen

const AVG_NET_MONTHLY_INCOME = (AVG_GROSS_YEARLY_INCOME - calculate_time_range_demurrage(AVG_GROSS_YEARLY_INCOME, make_tiers(INCOME_TAX_BRACKETS), 0, 1, 1, false)) / 12

const GDP_PER_CAPITA = 44361
# GDP per capita for Belgium in 2023.
# Source: https://www.vlaanderen.be/statistiek-vlaanderen/macro-economie/bruto-binnenlands-product-per-inwoner

const INCOME_PER_CAPITA = 293175000000 / POPULATION
# Source: https://www.nbb.be/doc/dq/n/dq3/histo/nnco23.pdf

const VAT_PER_CAPITA = 37083000000 / POPULATION # Total for 2023
# Source https://stat.nbb.be/Index.aspx?DataSetCode=TREASREV&lang=nl

const VAT = VAT_PER_CAPITA / GDP_PER_CAPITA # Average VAT rate

const EXPENSES_PER_CAPITA = 319141000000 / POPULATION
# Source: https://www.nbb.be/doc/dq/n/dq3/histo/nnco23.pdf

const INTEREST_COST_PER_CAPITA = 11818000000 / POPULATION
# Source: https://www.nbb.be/doc/dq/n/dq3/histo/nnco23.pdf

const PENSION_COST = 62900000000
const PENSION_COST_PER_CAPITA = PENSION_COST / POPULATION
# Source: https://www.ccrek.be/sites/default/files/Docs/181e_b_II_SocZk.pdf

const UNEMPLOYMENT_COST_PER_CAPITA = 6400000000 / POPULATION
# Source: https://www.ccrek.be/sites/default/files/Docs/181e_b_II_SocZk.pdf

const NET_EXPENSES_PER_CAPITA = EXPENSES_PER_CAPITA - INTEREST_COST_PER_CAPITA
const NET_MONTHLY_EXPENSES_PER_CAPITA = Currency(NET_EXPENSES_PER_CAPITA / 12)

const SUMSY_EXPENSES_PER_CAPITA = EXPENSES_PER_CAPITA - INTEREST_COST_PER_CAPITA - PENSION_COST_PER_CAPITA - UNEMPLOYMENT_COST_PER_CAPITA
const SUMSY_MONTHLY_EXPENSES_PER_CAPITA = Currency(SUMSY_EXPENSES_PER_CAPITA / 12)

const AVG_MONTHLY_PENSION = Currency(PENSION_COST / POP_65_PLUS / 12)

const GI_MIN_18 = 500
const GI_18_TO_64 = 2000
const GI_65_PLUS = AVG_MONTHLY_PENSION

const AVG_GI = (GI_MIN_18 * POP_MIN_18 + GI_18_TO_64 * POP_18_TO_64 + GI_65_PLUS * POP_65_PLUS) / POPULATION
const DEMOGRAPHIC_DEM = AVG_GI / M2_PER_CAPITA

const DEM_TAX = SUMSY_MONTHLY_EXPENSES_PER_CAPITA / M2_PER_CAPITA

const INEQUALITY_DATA = InequalityData(11198961.8532,     # Top 0.1%
                                        4765562.6228,    # Top 1%
                                        1661647.7412,    # Top 10%
                                        320263.1638,     # High middle 40%
                                        61451.1864,   # Low middle 40%
                                        -848.8797,       # Bottom 10%
                                        -52810.3328,     # Bottom 1%
                                        nothing,      # Bottom 0.1% - data not available
                                        money_per_head = M2_PER_CAPITA)
# Source https://wid.world - Belgium, 2023, Euro (accessed 0n 14-04-2025)

const MONTH = 1
const YEAR = 12

const NUM_ACTORS = 5000

const age_typed_population = Dict(:pop_min_18 => PERCENT_MIN_18,
                                :pop_18_to_64 => PERCENT_18_TO_64,
                                :pop_65_plus => PERCENT_65_PLUS)
    
const basic_sumsy_groups = Dict{Symbol, Tuple{Real, Real}}(:pop_min_18 => (GI_MIN_18, 0),
                                                        :pop_18_to_64 => (GI_18_TO_64, 0),
                                                        :pop_65_plus => (GI_65_PLUS, 0))

function post_process_sim_data!(actor_data,
                                model_data,
                                sumsy_sim::Bool = false)
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

    if sumsy_sim
        rename!(model_data,
                11 => :sumsy_data)
    end

    return actor_data, model_data
end

function post_process_no_tax_sim_data!(actor_data,
                                    model_data,
                                    sumsy_sim::Bool = false)
    rename!(actor_data,
            3 => :deposit,
            4 => :equity,
            5 => :wealth,
            6 => :income,
            7 => :expenses)

    rename!(model_data,
            2 => :num_actors,
            3 => :gdp,
            4 => :transactions,
            5 => :min_transaction,
            6 => :max_transaction)

    if sumsy_sim
        rename!(model_data,
                7 => :sumsy_data)
    end

    return actor_data, model_data
end

function add_gi_to_income!(model::ABM)
    for actor in allagents(model)
        add_income!(actor, max(0, actor.gi - actor.dem))
        actor.gi = CUR_0
        actor.dem = CUR_0
    end
end

function add_gi_and_adjust_income!(model::ABM; tax_interval::Int, vat_interval::Int)
    add_gi_to_income!(model)
    adjust_income_with_tax_share!(model, tax_interval = tax_interval, vat_interval = vat_interval)
end

function simulate_fixed_belgium(;sim_length::Int = 200 * YEAR,
                                num_actors::Int = NUM_ACTORS,
                                sumsy::Bool = false,
                                population_types = age_typed_population,
                                adjust_pop_up::Symbol = :pop_65_plus,
                                adjust_pop_down::Symbol = :pop_min_18,
                                gdp_scaling::Real = 1.0,
                                wealth_transfer::Real = 0.2,
                                inequality_data::Union{InequalityData, Nothing} = INEQUALITY_DATA,
                                tax_type::Union{TAX_TYPE, Nothing} = DEMURRAGE_TAX,
                                tax_brackets::DemSettings = DEM_TAX,
                                tax_interval::Int = tax_type == DEMURRAGE_TAX ? MONTH : YEAR,
                                vat::Real = VAT,
                                vat_interval::Int = 3 * MONTH,
                                percentage_tax_recipients::Real = 1)
    if sumsy
        model = create_sumsy_model(sumsy_interval = MONTH,
                                    model_behaviors = process_model_sumsy!)
        create_actor! = m -> create_sumsy_actor!(m,
                                                    sumsy = SuMSy(2000, 0, 2000 / M2_PER_CAPITA),
                                                    sumsy_interval = MONTH,
                                                    allow_negative_sumsy = true)
    else
        model = create_econo_model(MonetaryActor{Currency})
        create_actor! = m -> create_monetary_actor!(m)
    end

    sim_params = SimParams(sim_length)

    population_params = TypedPopulationParams(num_actors = num_actors,
                                                actor_types = population_types,
                                                adjust_up = adjust_pop_up,
                                                adjust_down = adjust_pop_down,
                                                create_actor! = create_actor!)

    transaction_params = GDPYardSaleParams(gdp_period = YEAR,
                                            gdp_per_capita = GDP_PER_CAPITA * gdp_scaling,
                                            wealth_transfer_range = wealth_transfer:wealth_transfer:wealth_transfer,
                                            minimal_wealth_transfer = 0,
                                            remove_broke_actors = true)

    if !isnothing(inequality_data)
        monetary_params = FixedWealthParams(m -> distribute_inequal!(m, inequality_data))
    else
        monetary_params = FixedWealthParams(m -> distribute_equal!(m, M2_PER_CAPITA))
    end

    if !isnothing(tax_type)
        tax_scheme = FixedTaxScheme(tax_type,
                                    tax_recipients = round(num_actors * percentage_tax_recipients),
                                    tax_interval = tax_interval,
                                    tax_brackets = tax_brackets,
                                    tax_free = 0,
                                    vat_interval = vat_interval,
                                    vat = vat)

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
                                            post_processing! = (ad, md) -> post_process_sim_data!(ad, md, false))
    else
        tax_scheme = nothing

        data_handler = IntervalDataHandler(interval = YEAR,
                                            actor_data_collectors = [deposit_collector,
                                                                    equity_collector,
                                                                    wealth_collector,
                                                                    income_collector!,
                                                                    expenses_collector!,
                                                                    :types],
                                            model_data_collectors = [nagents,
                                                                    gdp_collector!,
                                                                    transactions_collector!,
                                                                    min_transaction_collector!,
                                                                    max_transaction_collector!],
                                            post_processing! = (ad, md) -> post_process_no_tax_sim_data!(ad, md, false))
    end

    run_simulation(model,
                    sim_params = sim_params,
                    population_params = population_params,
                    monetary_params = monetary_params,
                    transaction_params = transaction_params,
                    tax_scheme = tax_scheme,
                    data_handler = data_handler,
                    termination_handler = TERMINATE_WHEN_ONE_NON_BROKE)
end

function simulate_sumsy_belgium(;sim_length::Int = 15 * YEAR,
                                num_actors::Int = NUM_ACTORS,
                                population_types = age_typed_population,
                                adjust_pop_up::Symbol = :pop_65_plus,
                                adjust_pop_down::Symbol = :pop_min_18,
                                allow_negative_sumsy::Bool = true,
                                demurrage::DemSettings = DEMOGRAPHIC_DEM,
                                gdp_scaling::Real = 1.0,
                                wealth_transfer::Real = 0.2,
                                sumsy_groups::Dict{Symbol, Tuple{Real, Real}} = basic_sumsy_groups,
                                inequality_data::InequalityData = INEQUALITY_DATA,
                                register_gi_as_income::Bool = true,
                                tax_type::TAX_TYPE = DEMURRAGE_TAX,
                                tax_brackets::DemSettings = DEM_TAX,
                                tax_interval::Int = tax_type == DEMURRAGE_TAX ? MONTH : YEAR,
                                vat::Real = VAT,
                                vat_interval::Int = 3 * MONTH,
                                percentage_tax_recipients::Real = 1)
    model = create_sumsy_model(sumsy_interval = MONTH,
                                model_behaviors = process_model_sumsy!)

    sim_params = SimParams(sim_length)
    population_params = RelativeTypedPopulationParams(num_actors = num_actors,
                                                    actor_types = population_types,
                                                    adjust_up = adjust_pop_up,
                                                    adjust_down = adjust_pop_down,
                                                    create_actor! = m -> create_sumsy_actor!(m,
                                                                                            sumsy = SuMSy(2000, 0, DEMOGRAPHIC_DEM),
                                                                                            sumsy_interval = MONTH,
                                                                                            allow_negative_sumsy = allow_negative_sumsy))
    transaction_params = GDPYardSaleParams(gdp_period = YEAR,
                                            gdp_per_capita = GDP_PER_CAPITA * gdp_scaling,
                                            wealth_transfer_range = wealth_transfer:wealth_transfer:wealth_transfer,
                                            minimal_wealth_transfer = 0,
                                            remove_broke_actors = false,
                                            adjust_income! = register_gi_as_income ? 
                                                                m -> add_gi_and_adjust_income!(m,
                                                                                                tax_interval = tax_scheme.tax_interval,
                                                                                                vat_interval = tax_scheme.vat_interval) :
                                                                m -> adjust_income_with_tax_share!(m,
                                                                                                    tax_interval = tax_scheme.tax_interval,
                                                                                                    vat_interval = tax_scheme.vat_interval))
    monetary_params = StandardSuMSyParams(sumsy_interval = MONTH,
                                            transactional = false,
                                            configure_sumsy_actors! = m -> type_based_sumsy_actors!(m, sumsy_groups, demurrage),
                                            distribute_wealth! = m -> distribute_inequal!(m,
                                                                                            inequality_data,
                                                                                            collect(keys(population_types))))
    tax_scheme = FixedTaxScheme(tax_type,
                                tax_recipients = round(num_actors * percentage_tax_recipients),
                                tax_interval = tax_interval,
                                tax_brackets = tax_brackets,
                                tax_free = 0,
                                vat_interval = vat_interval,
                                vat = vat)
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
                                                                failed_vat_collector!,
                                                                sumsy_data_collector!],
                                        post_processing! = post_process_sim_data!)

    run_simulation(model,
                    sim_params = sim_params,
                    population_params = population_params,
                    monetary_params = monetary_params,
                    transaction_params = transaction_params,
                    tax_scheme = tax_scheme,
                    data_handler = data_handler)
end