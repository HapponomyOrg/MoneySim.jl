using Random

abstract type TaxScheme{C <: FixedDecimal} end

"""
    collect_vat!(actor::BalanceActor, amount::Real, vat::Real)
    * actor: BalanceActor - The actor from which the VAT is collected.
    * amount: Real - The amount of the transaction.

    Used to collect VAT on every transaction.
    See beheviour models.
"""
function collect_vat!(actor::BalanceActor, amount::Real, vat::Real, vat_entry::BalanceEntry)
    if vat != 0
        model = actor.model
        vat = Currency(amount * vat)
        balance = get_balance(actor)
        book_asset!(balance, vat_entry, -vat)
        actor.paid_vat += vat
        model.vat_to_distribute += vat

        return vat
    else
        return CUR_0
    end
end

"""
    struct IncomeTaxScheme{C <: FixedDecimal} <: TaxScheme{C}
        * tax_brackets: DemTiers - The tax tax_brackets.
        * tax_free: C - The tax free amount.
        * num_tax_recipients: Int - The number of tax recipients.
        * distribute_taxes!: D - Function that distributes taxes among the recipients.
        * collect_vat!: V - The function that collects the VAT on every transaction.
                            It must take the arguments (actor, amount) and must be called when the transaction is processed.
"""
struct IncomeTaxScheme{C <: FixedDecimal, D <: Function, V <: Function} <: TaxScheme{C}
    tax_brackets::DemTiers
    tax_free::C
    num_tax_recipients::Int
    distribute_taxes!::D
    interval::Int
    collect_vat!::V
end

function IncomeTaxScheme(tax_brackets::DemSettings,
                        tax_free::Real,
                        num_tax_recipients::Int,
                        distribute_taxes!::Function,
                        interval::Int;
                        vat::Real = 0,
                        vat_entry::BalanceEntry = SUMSY_DEP)

    vat! = (x, y) -> collect_vat!(x, y, vat, vat_entry)

    return IncomeTaxScheme{Currency, typeof(distribute_taxes!), typeof(vat!)}(make_tiers(tax_brackets),
                                    tax_free,
                                    num_tax_recipients,
                                    distribute_taxes!,
                                    interval,
                                    vat!)
end

function set_tax_properties(model::ABM, tax_scheme::TaxScheme)
    properties = abmproperties(model)
    properties[:tax_scheme] = tax_scheme
    properties[:collected_taxes] = CUR_0
    properties[:vat_to_distribute] = CUR_0
    properties[:collected_vat] = CUR_0
    properties[:tax_recipients] = create_tax_recipients(model, tax_scheme.num_tax_recipients)

    for actor in allagents(model)
        actor.paid_tax = CUR_0
        actor.paid_vat = CUR_0
        actor.income = CUR_0
    end
end

function create_tax_recipients(model::ABM, num_tax_recipients::Int)
    tax_recipients = Vector(undef, num_tax_recipients)

    for i in 1:num_tax_recipients
        tax_recipients[i] = model[i]
    end

    return tax_recipients
end

"""
    distribute_taxes!(model::ABM, tax_amount::Currency)
    * model: ABM - The model.
    * tax_amount: Currency - The amount of taxes to distribute.

    Distributes taxes among the tax recipients. Called from tax handling functions.
"""
function distribute_taxes!(model::ABM, tax_amount::Currency)
    tax_recipients = model.tax_recipients
    vat_to_distribute = model.vat_to_distribute
    model.collected_vat += vat_to_distribute

    tax_amount += vat_to_distribute

    model.vat_to_distribute = CUR_0

    tax_share = tax_amount / length(tax_recipients)

    for actor in tax_recipients
        book_asset!(get_balance(actor), SUMSY_DEP, tax_share)
        actor.income += tax_share
    end

    extra = tax_amount - tax_share * length(tax_recipients)

    if extra != 0
        actor = tax_recipients[rand(1:length(tax_recipients))]
        book_asset!(get_balance(actor), SUMSY_DEP, extra)
        actor.income += extra
    end
end

function initialize_tax_scheme!(model::ABM, tax_scheme::IncomeTaxScheme)
    set_tax_properties(model, tax_scheme)

    add_model_behavior!(model, process_income_taxes!, position = 2)
end

function process_income_taxes!(model::ABM)
    step = get_step(model)
    income_taxes = model.tax_scheme
    tax_interval = income_taxes.interval

    if mod(step, tax_interval) == 0
        collected_tax = CUR_0

        for actor in allagents(model)
            income = actor.income
            tax = calculate_time_range_demurrage(income,
                                                    income_taxes.tax_brackets,
                                                    income_taxes.tax_free,
                                                    tax_interval,
                                                    tax_interval)
            book_asset!(get_balance(actor), SUMSY_DEP, -tax)
            actor.paid_tax += tax
            collected_tax += tax
        end

        model.collected_taxes += collected_tax
        income_taxes.distribute_taxes!(model, collected_tax)
    end
end

"""
    struct IncomeTaxScheme{C <: FixedDecimal} <: TaxScheme{C}
        * dem_tiers: DemTiers - The tax tax_brackets.
        * dem_free: C - The demurrage free amount.
        * num_tax_recipients: Int - The number of tax recipients.
        * distribute_taxes!: D - Function that distributes taxes among the recipients.
        * interval: Int - The interval over which demurrage is calculated.
        * transactional: Bool - Whether or not demurrage is calculated with every transaction.
        * collect_vat!: V - The function that collects the VAT on every transaction.
                            It must take the arguments (actor, amount) and must be called when the transaction is processed.
"""
struct DemurrageTaxScheme{C <: FixedDecimal, D <: Function, V <: Function} <: TaxScheme{C}
    dem_tiers::DemTiers
    dem_free::C
    num_tax_recipients::Int
    distribute_taxes!::D
    interval::Int
    transactional::Bool
    collect_vat!::V
end

function DemurrageTaxScheme(dem_tiers::DemSettings,
                            dem_free::Real,
                            num_tax_recipients::Int,
                            distribute_taxes!::Function,
                            interval::Int;
                            transactional::Bool = false,
                            vat::Real = 0,
                            vat_entry::BalanceEntry = SUMSY_DEP)

    vat! = (x, y) -> collect_vat!(x, y, vat, vat_entry)

    return DemurrageTaxScheme{Currency, typeof(distribute_taxes!), typeof(vat!)}(make_tiers(dem_tiers),
                                        dem_free,
                                        num_tax_recipients,
                                        distribute_taxes!,
                                        interval,
                                        transactional,
                                        vat!)
end

function initialize_tax_scheme!(model::ABM, tax_scheme::DemurrageTaxScheme)
    set_tax_properties(model, tax_scheme)

    add_model_behavior!(model, process_dem_taxes!, position = 2)
end

function process_dem_taxes!(model)
    step = get_step(model)
    dem_taxes = model.tax_scheme
    tax_interval = dem_taxes.interval

    if !dem_taxes.transactional && mod(step, tax_interval) == 0
        collected_tax = CUR_0

        for actor in allagents(model)
            balance = get_balance(actor)
            tax = calculate_time_range_demurrage(asset_value(balance, SUMSY_DEP),
                                                dem_taxes.dem_tiers,
                                                dem_taxes.dem_free,
                                                tax_interval,
                                                tax_interval)
            book_asset!(balance, SUMSY_DEP, -tax)
            actor.paid_tax += tax
            collected_tax += tax
        end

        model.collected_taxes += collected_tax
        dem_taxes.distribute_taxes!(model, collected_tax)
    end
end

# Function not yet used
function reimburse_contribution!(model::ABM, amount::Real)
    step = get_step(model)
    total_contribution = CUR_0
    total_reimburse = CUR_0

    for actor in allagents(model)
        total_contribution += paid_contribution(actor)
    end

    for actor in allagents(model)
        reimburse_amount = amount * paid_contribution(actor) / total_contribution
        book_sumsy!(get_balance(actor), reimburse_amount, timestamp = step)
        book_contribution!(actor, -amount)
        total_reimburse += reimburse_amount
    end

    book_asset!(model.contribution_balance, SUMSY_DEP, -total_reimburse)
end