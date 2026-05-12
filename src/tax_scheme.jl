using Random

abstract type TaxScheme{C <: FixedDecimal} end

@enum DistributionType D_TAX D_VAT

"""
    struct FixedTaxScheme{C <: FixedDecimal} <: TaxScheme{C}
        * type: TAX_TYPE
        * tax_recipients: Int - The number of tax recipients.
        * tax_calculation_interval: Int - The interval for tax calculation.
        * tax_redistribution_interval: Int - The interval to collect and distribute taxes. Must be <= tax calculation interval.
        * tax_brackets: DemTiers - The tax brackets.
        * tax_free: C - The tax free bracket.
        * add_tax_share_to_income: Bool - Whether or not to add the redistributed tax share to income.
        * vat_interval: Int - The interval vor VAT collection.
        * vat: Real - The VAT rate.
        * add_vat_share_to_income: Bool - Whether or not to add the redistributed VAT share to income.
        * initial_income!: Function - Set the initial income of the actors.
        * distribution_adjustment!: Function - Adjust the distribution amount.
                                                Takes the model, the distribution type (D_TAX or D_VAT) and the initial amount as a parameter and returns the adjusted amount.
    
    Data for tax and VAT collection and redistribution.
    The interval for tax calculation and tax redistribution can be different. In that case, partial collection and redistribution is handled at redistribution intervals.
    At the last interval all remaining taxes are collected and redistributed.
"""
struct FixedTaxScheme{C <: FixedDecimal, FI, FD} <: TaxScheme{C}
    type::TAX_TYPE
    tax_recipients::Int
    tax_calculation_interval::Int
    tax_redistribution_interval::Int
    tax_brackets::DemTiers
    tax_free::C
    add_tax_share_to_income::Bool
    vat_interval::Int
    vat::Real
    deduct_vat_from_taxes::Bool
    add_vat_share_to_income::Bool
    initial_income!::FI
    distribution_adjustment!::FD

    FixedTaxScheme(tax_type::TAX_TYPE;
                    tax_recipients::Int = 0,
                    tax_calculation_interval::Int = MONTH,
                    tax_redistribution_interval::Int = MONTH,
                    tax_brackets::DemSettings = 0,
                    tax_free::Real = 0,
                    add_tax_share_to_income::Bool = false,
                    vat_interval::Real = tax_calculation_interval,
                    vat::Real = 0,
                    deduct_vat_from_taxes::Bool = false,
                    add_vat_share_to_income::Bool = false,
                    initial_income!::Union{Nothing, Function} = nothing,
                    distribution_adjustment!::Union{Nothing, Function}) = new{Currency,
                                                                                typeof(initial_income!),
                                                                                typeof(distribution_adjustment!)}(
                                                            tax_type,
                                                            tax_recipients,
                                                            tax_calculation_interval,
                                                            min(tax_redistribution_interval, tax_calculation_interval),
                                                            make_tiers(tax_brackets),
                                                            tax_free,
                                                            add_tax_share_to_income,
                                                            vat_interval,
                                                            vat,
                                                            deduct_vat_from_taxes,
                                                            add_vat_share_to_income,
                                                            initial_income!,
                                                            distribution_adjustment!)
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
    properties[:add_tax_share_to_income] = tax_scheme.add_tax_share_to_income
    properties[:add_vat_share_to_income] = tax_scheme.add_vat_share_to_income

    properties[:tax_recipients] = create_tax_recipients(model, tax_scheme.tax_recipients)

    properties[:tax_redistribution_step] = 0

    properties[:data_collected_taxes] = CUR_0 # For data purposes
    properties[:data_collected_vat] = CUR_0 # For data purposes
    properties[:data_tax_faliures] = 0 # When the full tax can not be paid.
    properties[:data_vat_faliures] = 0 # WHen the full VAT can not be paid.

    properties[:distribution_adjustment!] = tax_scheme.distribution_adjustment!

    init_income! = tax_scheme.initial_income!

    for actor in allagents(model)
        actor.income = isnothing(init_income!) ? CUR_0 : init_income!(actor)
        actor.expenses = CUR_0 # Only to make sure the field exists

        actor.tax_deduction = CUR_0

        actor.taxable_income = CUR_0
        actor.tax_to_pay = CUR_0
        actor.data_paid_tax = CUR_0

        actor.vat_eligible = CUR_0
        actor.data_paid_vat = CUR_0

        actor.data_taxed_amount = CUR_0
        actor.data_tax_share = CUR_0
        actor.data_vat_share = CUR_0
    end

    add_model_behavior!(model,
                        m -> register_income_and_expenses!(m, tax_scheme.type))

    if tax_scheme.type == DEMURRAGE_TAX
        add_model_behavior!(model,
                            m -> calculate_dem_taxes!(m,
                                                    tax_scheme.tax_calculation_interval,
                                                    tax_scheme.tax_free,
                                                    tax_scheme.tax_brackets))
    elseif tax_scheme.type == INCOME_TAX
        add_model_behavior!(model,
                            m -> calculate_income_taxes!(m,
                                                        tax_scheme.tax_calculation_interval,
                                                        tax_scheme.tax_free,
                                                        tax_scheme.tax_brackets))

    add_model_behavior!(model, m -> collect_and_distribute_taxes!(m,
                                                                tax_scheme.tax_calculation_interval, # Make sure last cycle taxes are collected and redistributed before new calculation.
                                                                tax_scheme.tax_redistribution_interval))

    add_model_behavior!(model,
                        m -> collect_and_distribute_vat!(m,
                                            tax_scheme.vat_interval,
                                            tax_scheme.vat,
                                            tax_scheme.deduct_vat_from_taxes))
    end
end

function create_tax_recipients(model::ABM, num_tax_recipients::Int)
    tax_recipients = Vector(undef, num_tax_recipients)

    for i in 1:num_tax_recipients
        tax_recipients[i] = model[i]
    end

    return tax_recipients
end

function collect_and_distribute_vat!(model::ABM, vat_interval::Int, vat::Real, deduct_vat_from_taxes::Bool)
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

            if deduct_vat_from_taxes
                actor.tax_deduction += vat_to_pay # Deduct paid VAT from taxable income.
            end

            actor.vat_eligible = CUR_0
            actor.data_paid_vat += vat_to_pay

            collected_vat += vat_to_pay
        end

        model.data_collected_vat += collected_vat
        distribution_adjustment! = model.distribution_adjustment!

        if isnothing(distribution_adjustment!)
            amount_to_distribute = collected_vat
        else
            amount_to_distribute = distribution_adjustment!(model, D_VAT, collected_vat)
        end

        distribute_amount!(model, amount_to_distribute, :data_vat_share, model.add_vat_share_to_income)
    end
end

function calculate_taxes!(model::ABM,
                        tax_calculation_interval::Int,
                        tax_free::Real,
                        tax_brackets::DemTiers,
                        taxable::Function)                   
    if mod(get_step(model), tax_calculation_interval) == 0
        for actor in allagents(model)
            taxable_amount = taxable(actor) - actor.tax_deduction

            actor.tax_to_pay = calculate_time_range_demurrage(taxable_amount,
                                                            tax_brackets,
                                                            tax_free,
                                                            tax_calculation_interval,
                                                            tax_calculation_interval,
                                                            false)

            actor.taxable_income = CUR_0
            actor.tax_deduction = CUR_0
        end

        model.tax_redistribution_step = 0
    end
end

function calculate_income_taxes!(model::ABM,
                                tax_calculation_interval::Int,
                                tax_free::Real,
                                tax_brackets::DemTiers)    
    calculate_taxes!(model,
                    tax_calculation_interval,
                    tax_free,
                    tax_brackets,
                    a -> a.taxable_income)
end

function calculate_dem_taxes!(model,
                            tax_calculation_interval::Int,
                            dem_free::Real,
                            dem_tiers::DemTiers)
    calculate_taxes!(model,
                    tax_calculation_interval,
                    dem_free,
                    dem_tiers,
                    a -> asset_value(get_balance(a), SUMSY_DEP))
end

function distribute_amount!(model::ABM, collected_amount::Real, share_symbol::Symbol, add_share_to_income::Bool)
    tax_recipients = model.tax_recipients

    if !isempty(tax_recipients)
        share = Currency(collected_amount / length(tax_recipients))

        for actor in tax_recipients
            book_asset!(get_balance(actor), SUMSY_DEP, share)
            setproperty!(actor, share_symbol, getproperty(actor, share_symbol) + share)

            if add_share_to_income
                add_income!(actor, share)
            end
        end

        extra = collected_amount - share * length(tax_recipients)

        if extra != 0
            actor = tax_recipients[rand(1:length(tax_recipients))]
            book_asset!(get_balance(actor), SUMSY_DEP, extra)
            setproperty!(actor, share_symbol, getproperty(actor, share_symbol) + extra)

            if add_share_to_income
                add_income!(actor, extra)
            end
        end
    end
end

function collect_and_distribute_taxes!(model::ABM, calculation_interval::Int, redistribution_interval::Int)
    step = get_step(model)

    if mod(step, redistribution_interval) == 0 || mod(step, calculation_interval) == 0
        tax_coefficient = calculation_interval - model.tax_redistribution_step
        collected_tax = CUR_0

        for actor in allagents(model)
            balance = get_balance(actor)
            tax_slice = actor.tax_to_pay / tax_coefficient
                                                    
            if !book_asset!(balance, SUMSY_DEP, -tax_slice)
                tax_slice = asset_value(balance, SUMSY_DEP)
                book_asset!(balance, SUMSY_DEP, -tax_slice)
                model.data_tax_faliures += 1
            end

            actor.tax_to_pay -= tax_slice
            actor.data_taxed_amount += tax_slice
            actor.data_paid_tax += tax_slice
            collected_tax += tax_slice
        end

        model.data_collected_taxes += collected_tax
        distribution_adjustment! = model.distribution_adjustment!

        if isnothing(distribution_adjustment!)
            amount_to_distribute = collected_tax
        else
            amount_to_distribute = distribution_adjustment!(model, D_TAX, collected_tax)
        end

        distribute_amount!(model, amount_to_distribute, :data_tax_share, model.add_tax_share_to_income)
        model.tax_redistribution_step += 1
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