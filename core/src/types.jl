# Configuration and result types for MoneySimCore.
#
# Values are named and grouped by concern. No bare integer codes are used at
# call sites; enums live in small modules so they are always qualified.

module MoneyModel
    const Kind = Int32
    const FIXED = Int32(0)
    const SUMSY = Int32(1)
    const DEBT_BASED = Int32(2)
    const LOAN_CIRCUIT = Int32(3)
end

module TransactionModel
    const Kind = Int32
    const YARD_SALE = Int32(0)
    const CONSUMER_SUPPLIER = Int32(1)
end

module AdaptationMode
    const Kind = Int32
    const NONE = Int32(0)
    const TOTAL = Int32(1)
    const PER_ACTOR = Int32(2)
    const HALF_BALANCE = Int32(3)
end

module LoanRandomMode
    const Kind = Int32
    const FIXED = Int32(0)
    const GROWTH = Int32(1)
    const LOAN_RATE = Int32(2)
end

module TaxKind
    const Kind = Int32
    const NONE = Int32(0)
    const WEALTH = Int32(1)
    const INCOME = Int32(2)
    const DEMURRAGE = Int32(3)
end

module TaxRecipient
    const Kind = Int32
    const EVERYONE = Int32(0)
    const ONE_ACTOR = Int32(1)
    const DESTROY = Int32(2)
    const FIRST_N = Int32(3)
end

module WealthDistribution
    const Kind = Int32
    const EQUAL = Int32(0)
    const CUSTOM = Int32(1)
    const CONCENTRATED = Int32(2)
end

"""
    MoneyConfig

The money model and its parameters. `interval` is the number of simulation
steps between adjustments; guaranteed income and demurrage are applied once per
interval.
"""
struct MoneyConfig
    model::MoneyModel.Kind
    guaranteed_income::Money
    demurrage::DemTiers
    demurrage_free::Money
    interval::Int
    interest_rate::Int64
    transactional::Bool
    typed_guaranteed_income::Vector{Money}
    typed_demurrage_free::Vector{Money}
end

function MoneyConfig(; model::MoneyModel.Kind = MoneyModel.SUMSY,
                     guaranteed_income::Money = MONEY_ZERO,
                     demurrage::DemTiers = NO_DEM_TIERS,
                     demurrage_free::Money = MONEY_ZERO,
                     interval::Integer = 1,
                     interest_rate::Integer = 0,
                     transactional::Bool = false,
                     typed_guaranteed_income::Vector{Money} = Money[],
                     typed_demurrage_free::Vector{Money} = Money[])
    return MoneyConfig(model, guaranteed_income, demurrage, demurrage_free,
                       Int(interval), Int64(interest_rate), transactional,
                       typed_guaranteed_income, typed_demurrage_free)
end

"""
    TransactionConfig

Yard-sale transaction settings. `transfer_rate` is in ppm.
"""
struct TransactionConfig
    enabled::Bool
    transactions_per_step::Int
    transfer_rate::Int64
    minimal_transfer::Money
    wealth_advantage::Float64
    allow_negative::Bool
    model::TransactionModel.Kind
    suppliers::Int
    consumers_per_supplier::Int
    demand::Int
    price::Money
    suppliers_gi_eligible::Bool
end

function TransactionConfig(; enabled::Bool = false,
                           transactions_per_step::Integer = 0,
                           transfer_rate::Real = 0.2,
                           minimal_transfer::Money = MONEY_ZERO,
                           wealth_advantage::Real = 0.0,
                           allow_negative::Bool = false,
                           model::TransactionModel.Kind = TransactionModel.YARD_SALE,
                           suppliers::Integer = 0,
                           consumers_per_supplier::Integer = 0,
                           demand::Integer = 0,
                           price::Money = MONEY_ZERO,
                           suppliers_gi_eligible::Bool = false)
    return TransactionConfig(enabled, Int(transactions_per_step),
                             ppm(transfer_rate), minimal_transfer,
                             Float64(wealth_advantage), allow_negative,
                             model, Int(suppliers), Int(consumers_per_supplier),
                             Int(demand), price, suppliers_gi_eligible)
end

"""
    TaxConfig

Wealth-tax settings for the minimal path. Income and demurrage taxes are added
in Phase 4.
"""
struct TaxConfig
    kind::TaxKind.Kind
    rate::Int64
    interval::Int
    recipient::TaxRecipient.Kind
    recipient_actor::Int
    brackets::Vector{Money}
    bracket_rates::Vector{Int64}
    target_revenue::Money
    scale_to_target::Bool
    notional::Vector{Money}
    allow_negative::Bool
end

function TaxConfig(; kind::TaxKind.Kind = TaxKind.NONE,
                   rate::Real = 0.0,
                   interval::Integer = 0,
                   recipient::TaxRecipient.Kind = TaxRecipient.EVERYONE,
                   recipient_actor::Integer = 0,
                   brackets::Vector{Money} = Money[],
                   bracket_rates::Vector{Int64} = Int64[],
                   target_revenue::Money = MONEY_ZERO,
                   scale_to_target::Bool = false,
                   notional::Vector{Money} = Money[],
                   allow_negative::Bool = false)
    return TaxConfig(kind, ppm(rate), Int(interval), recipient,
                     Int(recipient_actor), brackets, bracket_rates,
                     target_revenue, scale_to_target, notional, allow_negative)
end

"""
    GovernmentConfig

Optional government sector. When `deficit_spending` is on, a shortfall between
`expenses` and the tax collected is created as money and added to public debt.
"""
struct GovernmentConfig
    enabled::Bool
    expenses::Money
    deficit_spending::Bool
    initial_debt::Money
end

function GovernmentConfig(; enabled::Bool = false,
                         expenses::Money = MONEY_ZERO,
                         deficit_spending::Bool = false,
                         initial_debt::Money = MONEY_ZERO)
    return GovernmentConfig(enabled, expenses, deficit_spending, initial_debt)
end

"""
    GdpConfig

GDP sets a per-step transaction-volume target. It is not money and is not
booked as income. `growth_ppm` is a yearly rate, compounded monthly.
"""
struct GdpConfig
    enabled::Bool
    per_capita::Money
    growth_ppm::Int64
    interval::Int
end

function GdpConfig(; enabled::Bool = false,
                   per_capita::Money = MONEY_ZERO,
                   growth_ppm::Integer = 0,
                   interval::Integer = 1)
    return GdpConfig(enabled, per_capita, Int64(growth_ppm), Int(interval))
end

"""
    AdaptationConfig

Money injection and destruction. Amounts are totals per interval, split
 equally among alive actors.
"""
struct AdaptationConfig
    inject_mode::AdaptationMode.Kind
    inject_amount::Money
    inject_interval::Int
    inject_one_time::Bool
    destroy_mode::AdaptationMode.Kind
    destroy_amount::Money
    destroy_interval::Int
    destroy_one_time::Bool
    equal_distribution::Bool
    equal_interval::Int
end

function AdaptationConfig(; inject_mode::AdaptationMode.Kind = AdaptationMode.NONE,
                          inject_enabled::Union{Nothing, Bool} = nothing,
                          inject_amount::Money = MONEY_ZERO,
                          inject_interval::Integer = 1,
                          inject_one_time::Bool = false,
                          destroy_mode::AdaptationMode.Kind = AdaptationMode.NONE,
                          destroy_enabled::Union{Nothing, Bool} = nothing,
                          destroy_amount::Money = MONEY_ZERO,
                          destroy_interval::Integer = 1,
                          destroy_one_time::Bool = false,
                          equal_distribution::Bool = false,
                          equal_interval::Integer = 0)
    resolved_inject = inject_enabled === nothing ? inject_mode :
        (inject_enabled ? AdaptationMode.TOTAL : AdaptationMode.NONE)
    resolved_destroy = destroy_enabled === nothing ? destroy_mode :
        (destroy_enabled ? AdaptationMode.TOTAL : AdaptationMode.NONE)
    return AdaptationConfig(resolved_inject, inject_amount, Int(inject_interval),
                            inject_one_time, resolved_destroy, destroy_amount,
                            Int(destroy_interval), destroy_one_time,
                            equal_distribution, Int(equal_interval))
end

"""
    VatConfig

Value-added tax collected on accumulated income. `rate` is the headline rate
in ppm; the collected amount uses `rate / (1 + rate)`. When
`deduct_from_taxes` is set, collected VAT reduces the next tax assessment.
"""
struct VatConfig
    enabled::Bool
    rate::Int64
    interval::Int
    deduct_from_taxes::Bool
    recipient::TaxRecipient.Kind
    recipient_actor::Int
end

function VatConfig(; enabled::Bool = false,
                   rate::Real = 0.0,
                   interval::Integer = 0,
                   deduct_from_taxes::Bool = false,
                   recipient::TaxRecipient.Kind = TaxRecipient.EVERYONE,
                   recipient_actor::Integer = 0)
    return VatConfig(enabled, ppm(rate), Int(interval),
                     deduct_from_taxes, recipient, Int(recipient_actor))
end

"""
    BankConfig

A designated bank actor. Each period it earns interest on outstanding loans,
receives principal repayment (destroying money), and lends new money to the
poorest actors (creating money).
"""
struct BankConfig
    enabled::Bool
    actor_index::Int
    repayment_rate::Int64
    lending_amount::Money
    lending_targets::Int
end

function BankConfig(; enabled::Bool = false,
                    actor_index::Integer = 0,
                    repayment_rate::Real = 0.0,
                    lending_amount::Money = MONEY_ZERO,
                    lending_targets::Integer = 0)
    return BankConfig(enabled, Int(actor_index), ppm(repayment_rate),
                      lending_amount, Int(lending_targets))
end

"""
    LoanCircuitConfig

Paper-1 post-Keynesian loan circuit. `mode = 0` is fixed growth; `mode = 1`
is fixed loan rate. In loan-rate mode the loan book lives in `SimState` and
money in circulation is resynchronised pro-rata to the aggregate pool.
"""
struct LoanCircuitConfig
    enabled::Bool
    profit_rate::Int64
    maturity::Int
    mode::Int32
    random_mode::LoanRandomMode.Kind
    min_value::Int64
    max_value::Int64
    min_maturity::Int
    max_maturity::Int
    relative_profit::Int64
    no_loss::Bool
end

function LoanCircuitConfig(; enabled::Bool = false,
                           profit_rate::Real = 0.0,
                           maturity::Integer = 1,
                           mode::Integer = 1,
                           random_mode::LoanRandomMode.Kind = LoanRandomMode.FIXED,
                           min_value::Real = 0.0,
                           max_value::Real = 0.0,
                           min_maturity::Integer = 1,
                           max_maturity::Integer = 1,
                           relative_profit::Real = 0.0,
                           no_loss::Bool = true)
    return LoanCircuitConfig(enabled, ppm(profit_rate), Int(maturity),
                             Int32(mode), random_mode, ppm(min_value),
                             ppm(max_value), Int(min_maturity),
                             Int(max_maturity), ppm(relative_profit),
                             no_loss)
end

"""
    WealthConfig

Initial wealth distribution. For `CUSTOM`, `custom[i]` is actor `i`'s starting
wealth; missing entries are zero.
"""
struct WealthConfig
    distribution::WealthDistribution.Kind
    equal_amount::Money
    custom::Vector{Money}
end

function WealthConfig(; distribution::WealthDistribution.Kind = WealthDistribution.EQUAL,
                      equal_amount::Money = MONEY_ZERO,
                      custom::Vector{Money} = Money[])
    return WealthConfig(distribution, equal_amount, custom)
end

"""
    PopulationConfig

Fixed population for the minimal path. `gi_eligible` is empty for "everyone is
eligible", otherwise a 1/0 vector of length `count`.
"""
struct PopulationConfig
    count::Int
    gi_eligible::Vector{UInt8}
    birth_rate::Int64
    death_rate::Int64
    aging_interval::Int
    aging_rate::Int64
    birth_wealth::Money
    gi_child::Bool
    gi_adult::Bool
    gi_elder::Bool
    typed_gi::Bool
    age_shares::Vector{Int64}
end

function PopulationConfig(; count::Integer = 100,
                          gi_eligible::Vector{UInt8} = UInt8[],
                          birth_rate::Real = 0.0,
                          death_rate::Real = 0.0,
                          aging_interval::Integer = 0,
                          aging_rate::Real = 0.0,
                          birth_wealth::Money = MONEY_ZERO,
                          gi_child::Bool = true,
                          gi_adult::Bool = true,
                          gi_elder::Bool = true,
                          typed_gi::Bool = false,
                          age_shares::Vector{Int64} = Int64[])
    return PopulationConfig(Int(count), gi_eligible,
                            ppm(birth_rate), ppm(death_rate),
                            Int(aging_interval), ppm(aging_rate),
                            birth_wealth, gi_child, gi_adult, gi_elder, typed_gi,
                            age_shares)
end

"""
    SimConfig

The full simulation configuration. `periods` counts simulation steps;
`record_interval` controls how often aggregates are recorded.
"""
struct SimConfig
    periods::Int
    seed::UInt64
    record_interval::Int
    money::MoneyConfig
    wealth::WealthConfig
    transactions::TransactionConfig
    tax::TaxConfig
    population::PopulationConfig
    government::GovernmentConfig
    gdp::GdpConfig
    adaptations::AdaptationConfig
    bank::BankConfig
    loan_circuit::LoanCircuitConfig
    vat::VatConfig
end

function SimConfig(; periods::Integer = 100,
                   seed::Integer = 42,
                   record_interval::Integer = 1,
                   money::MoneyConfig = MoneyConfig(),
                   wealth::WealthConfig = WealthConfig(),
                   transactions::TransactionConfig = TransactionConfig(),
                   tax::TaxConfig = TaxConfig(),
                   population::PopulationConfig = PopulationConfig(),
                   government::GovernmentConfig = GovernmentConfig(),
                   gdp::GdpConfig = GdpConfig(),
                   adaptations::AdaptationConfig = AdaptationConfig(),
                   bank::BankConfig = BankConfig(),
                   loan_circuit::LoanCircuitConfig = LoanCircuitConfig(),
                   vat::VatConfig = VatConfig())
    return SimConfig(Int(periods), UInt64(seed), Int(record_interval), money,
                     wealth, transactions, tax, population, government, gdp,
                     adaptations, bank, loan_circuit, vat)
end

const CONFIG_OK = Int32(0)
const CONFIG_BAD_PERIODS = Int32(1)
const CONFIG_BAD_RECORD_INTERVAL = Int32(2)
const CONFIG_BAD_POPULATION = Int32(3)
const CONFIG_BAD_MONEY_INTERVAL = Int32(4)
const CONFIG_BAD_TAX_INTERVAL = Int32(5)
const CONFIG_BAD_WEALTH = Int32(6)
const CONFIG_BAD_TRANSFERS = Int32(7)
const CONFIG_BAD_TAX_BRACKETS = Int32(8)

"""
    validate_config(cfg) -> Int32

Numeric validation code for the wasm ABI. Returns `CONFIG_OK` on success.
"""
function validate_config(cfg::SimConfig)::Int32
    cfg.periods > 0 || return CONFIG_BAD_PERIODS
    cfg.record_interval > 0 || return CONFIG_BAD_RECORD_INTERVAL
    mod(cfg.periods, cfg.record_interval) == 0 || return CONFIG_BAD_RECORD_INTERVAL
    cfg.population.count > 0 || return CONFIG_BAD_POPULATION
    cfg.money.interval > 0 || return CONFIG_BAD_MONEY_INTERVAL
    cfg.tax.interval >= 0 || return CONFIG_BAD_TAX_INTERVAL
    if cfg.wealth.distribution === WealthDistribution.CUSTOM &&
       length(cfg.wealth.custom) < cfg.population.count
        return CONFIG_BAD_WEALTH
    end
    if cfg.transactions.enabled && cfg.transactions.transactions_per_step < 0
        return CONFIG_BAD_TRANSFERS
    end
    if cfg.tax.kind === TaxKind.INCOME || cfg.tax.kind === TaxKind.DEMURRAGE
        (isempty(cfg.tax.bracket_rates) ||
         length(cfg.tax.brackets) != length(cfg.tax.bracket_rates)) &&
            return CONFIG_BAD_TAX_BRACKETS
    end
    if cfg.vat.enabled && cfg.vat.interval <= 0
        return CONFIG_BAD_TAX_INTERVAL
    end
    if !isempty(cfg.population.gi_eligible) &&
       length(cfg.population.gi_eligible) != cfg.population.count
        return CONFIG_BAD_POPULATION
    end
    return CONFIG_OK
end

export MoneyModel, TransactionModel, AdaptationMode, LoanRandomMode
export TaxKind, TaxRecipient, WealthDistribution
export MoneyConfig, TransactionConfig, TaxConfig, VatConfig, WealthConfig
export PopulationConfig
export GovernmentConfig, GdpConfig, AdaptationConfig, BankConfig, LoanCircuitConfig, SimConfig
export CONFIG_OK, CONFIG_BAD_PERIODS, CONFIG_BAD_RECORD_INTERVAL
export CONFIG_BAD_POPULATION, CONFIG_BAD_MONEY_INTERVAL, CONFIG_BAD_TAX_INTERVAL
export CONFIG_BAD_WEALTH, CONFIG_BAD_TRANSFERS, CONFIG_BAD_TAX_BRACKETS, validate_config
