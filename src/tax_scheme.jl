using Random

@enum TAX_TYPE INCOME_TAX = 1 DEMURRAGE_TAX = 2

abstract type TaxScheme{C <: FixedDecimal} end

"""
    struct FixedTaxScheme{C <: FixedDecimal} <: TaxScheme{C}
    * type: TAX_TYPE
    * tax_recipients: Int - The number of tax recipients.
    * tax_interval: Int - The interval for tax collection.
    * tax_brackets: DemTiers - The tax brackets.
    * tax_free: C - The tax free bracket.
    * vat_interval: Int - The interval vor VAT collection.
    * vat: Real - The VAT rate.
    
"""
struct FixedTaxScheme{C <: FixedDecimal} <: TaxScheme{C}
    type::TAX_TYPE
    tax_recipients::Int
    tax_interval::Int
    tax_brackets::DemTiers
    tax_free::C
    vat_interval::Int
    vat::Real
end

function FixedTaxScheme(tax_type::TAX_TYPE;
                        tax_recipients::Int,
                        tax_interval::Int,
                        tax_brackets::DemSettings,
                        tax_free::Real,
                        vat_interval::Real = tax_interval,
                        vat::Real = 0)

    return FixedTaxScheme{Currency}(tax_type,
                                    tax_recipients,
                                    tax_interval,
                                    make_tiers(tax_brackets),
                                    tax_free,
                                    vat_interval,
                                    vat)
end

function register_income_and_expenses(model::ABM)
    for actor in allagents(model)
        actor.periodic_income = actor.income
        actor.taxable_income += actor.income
        actor.vat_eligible += actor.income
        actor.periodic_expenses += actor.expenses
    end
end

function initialize_tax_scheme!(model::ABM, tax_scheme::FixedTaxScheme)
    properties = abmproperties(model)
    properties[:collected_taxes] = CUR_0
    properties[:collected_vat] = CUR_0
    properties[:tax_recipients] = create_tax_recipients(model, tax_scheme.tax_recipients)
    properties[:tax_faliures] = 0 # When the full tax can not be paid.
    properties[:vat_faliures] = 0 # WHen the full VAT can not be paid.

    for actor in allagents(model)
        # Data collection purposes
        actor.periodic_income = CUR_0

        actor.taxable_income = CUR_0
        actor.paid_tax = CUR_0
        actor.tax_share = CUR_0

        actor.vat_eligible = CUR_0
        actor.paid_vat = CUR_0
        actor.vat_share = CUR_0

        actor.periodic_expenses = CUR_0
    end

    add_model_behavior!(model,
                        register_income_and_expenses,
                        position = 2)

    add_model_behavior!(model,
                        x -> collect_vat!(x,
                                            tax_scheme.vat_interval,
                                            tax_scheme.vat),
                        position = 3)

    if tax_scheme.type == DEMURRAGE_TAX
        add_model_behavior!(model,
                            x -> process_dem_taxes!(x,
                                                    tax_scheme.tax_interval,
                                                    tax_scheme.tax_free,
                                                    tax_scheme.tax_brackets),
                            position = 4)
    elseif tax_scheme.type == INCOME_TAX
        add_model_behavior!(model,
                            x -> process_income_taxes!(x,
                                                        tax_scheme.tax_interval,
                                                        tax_scheme.tax_free,
                                                        tax_scheme.tax_brackets),
                            position = 4)
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
function distribute_taxes!(model::ABM, tax_amount::Currency, tax_field::Symbol)
    tax_recipients = model.tax_recipients

    tax_share = tax_amount / length(tax_recipients)

    for actor in tax_recipients
        book_asset!(get_balance(actor), SUMSY_DEP, tax_share)
        actor.properties[tax_field] += tax_share
    end

    extra = tax_amount - tax_share * length(tax_recipients)

    if extra != 0
        actor = tax_recipients[rand(1:length(tax_recipients))]
        book_asset!(get_balance(actor), SUMSY_DEP, extra)
        actor.properties[tax_field] += extra
    end
end

function collect_vat!(model::ABM, vat_interval::Int, vat::Real)
    if mod(get_step(model), vat_interval) == 0
        collected_vat = CUR_0

        for actor in allagents(model)
            actor.vat_eligible += actor.vat_share # Add income from redistributed VAT.
            actor.taxable_income += actor.vat_share
            actor.vat_share = CUR_0

            vat_to_pay = Currency(actor.vat_eligible * vat)

            if !book_asset!(get_balance(actor), SUMSY_DEP, -vat_to_pay)
                # Only happens when negative balances are not allowed.
                vat_to_pay = asset_value(get_balance(actor), SUMSY_DEP)
                book_asset!(get_balance(actor), SUMSY_DEP, -vat_to_pay)
                model.vat_faliures += 1
            end

            actor.vat_eligible = CUR_0
            actor.paid_vat += vat_to_pay
            actor.taxable_income -= vat_to_pay # Deduct paid VAT from taxable income.
            collected_vat += vat_to_pay
        end

        distribute_taxes!(model, collected_vat, :vat_share)

        model.collected_vat += collected_vat
    end
end

function process_taxes!(model::ABM,
                        tax_interval::Int,
                        tax_free::Real,
                        tax_brackets::DemTiers,
                        taxable::F) where {F <: Function}                    
    if mod(get_step(model), tax_interval) == 0
        collected_tax = CUR_0

        for actor in allagents(model)
            actor.taxable_income += actor.tax_share # Add income from redistributed taxes.
            actor.vat_eligible += actor.tax_share # That income is also eligible for VAT.
            actor.tax_share = CUR_0
            balance = get_balance(actor)

            tax = calculate_time_range_demurrage(taxable(actor),
                                                    tax_brackets,
                                                    tax_free,
                                                    tax_interval,
                                                    tax_interval)
                                                    
            if !book_asset!(balance, SUMSY_DEP, -tax)
                tax = asset_value(balance, SUMSY_DEP)
                book_asset!(balance, SUMSY_DEP, -tax)
                model.tax_faliures += 1
            end

            actor.taxable_income = CUR_0
            actor.paid_tax += tax
            collected_tax += tax
        end

        model.collected_taxes += collected_tax
        distribute_taxes!(model, collected_tax, :tax_share)
    end
end

function process_income_taxes!(model::ABM,
                                tax_interval::Int,
                                tax_free::Real,
                                tax_brackets::DemTiers)
    process_taxes!(model,
                    tax_interval,
                    tax_free,
                    tax_brackets,
                    x -> x.income)
end

function process_dem_taxes!(model,
                            tax_interval::Int,
                            dem_free::Real,
                            dem_tiers::DemTiers)
    process_taxes!(model,
                    tax_interval,
                    dem_free,
                    dem_tiers,
                    x -> asset_value(get_balance(x), SUMSY_DEP))
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