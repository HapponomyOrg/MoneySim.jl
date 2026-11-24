# Simulation orchestration.

struct ConfigError <: Exception
    code::Int32
end

Base.showerror(io::IO, error::ConfigError) =
    print(io, "invalid SimConfig (code ", error.code, ")")

function _resize_results!(results::ResultBuffers, count::Int)
    length(results.gini) == count && return results
    resize!(results.gini, count)
    resize!(results.mean, count)
    resize!(results.total, count)
    resize!(results.min, count)
    resize!(results.max, count)
    resize!(results.income_gini, count)
    resize!(results.shares, count * 6)
    resize!(results.income_shares, count * 6)
    resize!(results.tax_collected, count)
    resize!(results.tax_scale, count)
    resize!(results.government_debt, count)
    resize!(results.vat_collected, count)
    resize!(results.loan_debt, count)
    resize!(results.loan_equity, count)
    resize!(results.loan_issued, count)
    resize!(results.growth_ratio, count)
    resize!(results.profit_ratio, count)
    resize!(results.loan_ratio, count)
    return results
end

"""
    run_simulation!(cfg, state, results) -> SimResult

Run the configured periods over an existing state and result buffer.

The step order mirrors the legacy MoneySim orchestration: population, money
system, income registration, tax assessment/collection, VAT, transactions, and
model adaptations. Data is recorded at the end of the step.
"""
function run_simulation!(cfg::SimConfig, state::SimState, results::ResultBuffers;
                         initialize::Bool = true)
    records = div(cfg.periods, cfg.record_interval)
    _resize_results!(results, records)

    initialize && reset_state!(state, cfg)
    rng = Rng(cfg.seed)
    index = 0

    for period in 1:cfg.periods
        state.loan_issued = MONEY_ZERO
        state.loan_growth = 0.0
        state.loan_profit = 0.0
        population_step!(state, cfg.population, period, rng)
        step_money!(state, cfg.money, cfg.bank, cfg.loan_circuit, period, rng)
        if cfg.money.model === MoneyModel.LOAN_CIRCUIT && state.loan_collapsed
            break
        end

        # Income from the previous step is booked before the tax assessment,
        # matching MoneySim's behavior order (register → calculate → VAT →
        # collect → transactions → adaptations).
        register_income!(state)

        record_row = mod(period, cfg.record_interval) == 0
        if record_row
            index += 1
            record_income!(results, state, index)
        end

        collected = tax_step!(state, cfg.tax, cfg.money, period)
        vat_step!(state, cfg.vat, cfg.tax, period)
        government_step!(state, cfg.government, cfg.tax, collected)
        state.tax_accum = state.tax_accum + collected

        transactions_step!(state, cfg.transactions, cfg.gdp, cfg.money, rng, period)
        adaptations_step!(state, cfg.adaptations, cfg.money, period)

        if record_row
            record_wealth!(results, state, index, state.tax_accum)
            state.tax_accum = MONEY_ZERO
        end
    end

    _resize_results!(results, index)
    return SimResult(results, index)
end

"""
    run_simulation(cfg) -> SimResult

Allocate state and result buffers, validate the configuration, and run.
"""
function run_simulation(cfg::SimConfig)
    code = validate_config(cfg)
    code == CONFIG_OK || throw(ConfigError(code))

    state = SimState(cfg.population.count)
    records = div(cfg.periods, cfg.record_interval)
    results = ResultBuffers(records)
    return run_simulation!(cfg, state, results)
end

simulate(cfg::SimConfig) = run_simulation(cfg)

export ConfigError, run_simulation, run_simulation!, simulate
