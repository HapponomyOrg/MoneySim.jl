using Random

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
    FixedTaxScheme(tax_type::TAX_TYPE;
                    tax_recipients::Int = 0,
                    tax_interval::Int = 1,
                    tax_brackets::DemSettings = 0,
                    tax_free::Real = 0,
                    vat_interval::Real = tax_interval,
                    vat::Real = 0) = new{Currency}(
                                        tax_type,
                                        tax_recipients,
                                        tax_interval,
                                        make_tiers(tax_brackets),
                                        tax_free,
                                        vat_interval,
                                        vat)
end

function register_income_and_expenses!(model::ABM, tax_type::TAX_TYPE)
    for actor in allagents(model)
        actor.vat_eligible += actor.income

        if tax_type == INCOME_TAX
            actor.taxable_income += actor.income
        end
    end
end

function initialize_tax_scheme!(model::ABM, tax_scheme::FixedTaxScheme)
    properties = abmproperties(model)
    properties[:data_collected_taxes] = CUR_0 # For data purposes
    properties[:data_collected_vat] = CUR_0 # For data purposes
    properties[:tax_recipients] = create_tax_recipients(model, tax_scheme.tax_recipients)
    properties[:data_tax_faliures] = 0 # When the full tax can not be paid.
    properties[:data_vat_faliures] = 0 # WHen the full VAT can not be paid.

    for actor in allagents(model)
        actor.income = CUR_0 # Only to make sure the field exists
        actor.expenses = CUR_0 # Only to make sure the field exists

        actor.taxable_income = CUR_0
        actor.data_paid_tax = CUR_0

        actor.vat_eligible = CUR_0
        actor.data_paid_vat = CUR_0

        actor.data_taxed_amount = CUR_0
        actor.tax_share = CUR_0
        actor.vat_share = CUR_0
    end

    add_model_behavior!(model,
                        m -> register_income_and_expenses!(m, tax_scheme.type))

    add_model_behavior!(model,
                        m -> collect_vat!(m,
                                            tax_scheme.vat_interval,
                                            tax_scheme.vat,
                                            tax_scheme.type == INCOME_TAX))

    if tax_scheme.type == DEMURRAGE_TAX
        add_model_behavior!(model,
                            m -> collect_dem_taxes!(m,
                                                    tax_scheme.tax_interval,
                                                    tax_scheme.tax_free,
                                                    tax_scheme.tax_brackets))
    elseif tax_scheme.type == INCOME_TAX
        add_model_behavior!(model,
                            m -> collect_income_taxes!(m,
                                                        tax_scheme.tax_interval,
                                                        tax_scheme.tax_free,
                                                        tax_scheme.tax_brackets))
    end
end

function create_tax_recipients(model::ABM, num_tax_recipients::Int)
    tax_recipients = Vector(undef, num_tax_recipients)

    for i in 1:num_tax_recipients
        tax_recipients[i] = model[i]
    end

    return tax_recipients
end

function collect_vat!(model::ABM, vat_interval::Int, vat::Real, adjust_taxable_income::Bool)
    if mod(get_step(model), vat_interval) == 0
        collected_vat = CUR_0

        for actor in allagents(model)
            balance = get_balance(actor)
            vat_to_pay = Currency(actor.vat_eligible * vat)

            if !book_asset!(balance, SUMSY_DEP, -vat_to_pay)
                vat_to_pay = asset_value(balance, SUMSY_DEP)
                book_asset!(balance, SUMSY_DEP, -vat_to_pay)
                model.data_vat_faliures += 1
            end

            if adjust_taxable_income
                actor.taxable_income -= vat_to_pay # Deduct paid VAT from taxable income.
            end

            actor.vat_eligible = CUR_0
            actor.data_paid_vat += vat_to_pay

            collected_vat += vat_to_pay
        end

        model.data_collected_vat += collected_vat
        distribute_amount!(model, collected_vat, :vat_share)
    end
end

function collect_taxes!(model::ABM,
                        tax_interval::Int,
                        tax_free::Real,
                        tax_brackets::DemTiers,
                        taxable::Function)                   
    if mod(get_step(model), tax_interval) == 0
        collected_tax = CUR_0

        for actor in allagents(model)
            balance = get_balance(actor)
            taxable_amount = taxable(actor)

            tax = calculate_time_range_demurrage(taxable_amount,
                                                    tax_brackets,
                                                    tax_free,
                                                    tax_interval,
                                                    tax_interval,
                                                    false)
                                                    
            if !book_asset!(balance, SUMSY_DEP, -tax)
                tax = asset_value(balance, SUMSY_DEP)
                book_asset!(balance, SUMSY_DEP, -tax)
                model.data_tax_faliures += 1
            end

            actor.data_taxed_amount += taxable_amount
            actor.taxable_income = CUR_0
            actor.data_paid_tax += tax
            collected_tax += tax
        end

        model.data_collected_taxes += collected_tax
        distribute_amount!(model, collected_tax, :tax_share)
    end
end

function collect_income_taxes!(model::ABM,
                                tax_interval::Int,
                                tax_free::Real,
                                tax_brackets::DemTiers)    
    collect_taxes!(model,
                    tax_interval,
                    tax_free,
                    tax_brackets,
                    a -> a.taxable_income)
end

function collect_dem_taxes!(model,
                            tax_interval::Int,
                            dem_free::Real,
                            dem_tiers::DemTiers)
    collect_taxes!(model,
                    tax_interval,
                    dem_free,
                    dem_tiers,
                    a -> asset_value(get_balance(a), SUMSY_DEP))
end

function distribute_amount!(model::ABM, collected_amount::Real, share_symbol::Symbol)
    tax_recipients = model.tax_recipients

    if !isempty(tax_recipients)
        share = Currency(collected_amount / length(tax_recipients))

        for actor in tax_recipients
            book_asset!(get_balance(actor), SUMSY_DEP, share)
            setproperty!(actor, share_symbol, getproperty(actor, share_symbol) + share)
        end

        extra = collected_amount - share * length(tax_recipients)

        if extra != 0
            actor = tax_recipients[rand(1:length(tax_recipients))]
            book_asset!(get_balance(actor), SUMSY_DEP, extra)
            setproperty!(actor, share_symbol, getproperty(actor, share_symbol) + extra)
        end
    end
end

function add_share_to_income!(actor::AbstractActor,
                                share_symbol::Symbol,
                                share::Real,
                                interval::Int,
                                step::Int)
    if mod(step, interval) == 0
        add_income!(actor, getproperty(actor, share_symbol))
        setproperty!(actor, share_symbol, CUR_0)
    else
        partial_share = Currency(share / mod(step, interval))
        add_income!(actor, partial_share)
        setproperty!(actor, share_symbol, share - partial_share)
    end
end

"""
    adjust_income_with_tax_share!(model::ABM)
    * model::ABM : the model to distribute wealth in.

    Adjusts the income of all actors to account for the tax share.
    The tax share is spread out over the entire tax period so that the number of transactions is not too heaviliy affected in the first periods.
"""
function adjust_income_with_tax_share!(model::ABM; tax_interval::Int, vat_interval::Int)
    for actor in allagents(model)
        add_share_to_income!(actor, :tax_share, actor.tax_share, tax_interval, get_step(model))
        add_share_to_income!(actor, :vat_share, actor.vat_share, vat_interval, get_step(model))
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