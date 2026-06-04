using Random

abstract type TaxScheme{C <: FixedDecimal} end

@enum CollectionType D_TAX D_VAT

"""
    struct FixedTaxScheme{C <: FixedDecimal} <: TaxScheme{C}
        * type: TAX_TYPE
        * tax_recipients: Int - The number of tax recipients.
        * tax_calculation_interval: Int - The interval for tax calculation.
        * tax_redistribution_interval: Int - The interval to collect and distribute taxes. Must be <= tax calculation interval.
        * get_tax: Function - Returns the tax brackets. Can be DemSettings or DemTiers. Takes the model and calculation_interval as parameters.
        * vat_interval: Int - The interval vor VAT collection.
        * get_vat: Function - Get the VAT rate. Takes the model and calculation interval as parameters. Returns a number between 0 and 1.
        * initial_income!: Function - Set the initial income of the actors.
        * adjust_distribution!: Function - Adjust the distribution amount.
                                            Takes the model, the collection type (D_TAX or D_VAT) and the initial amount as a parameter and returns the adjusted amount.
        * adjust_tax!: Function - Adjust the tax brackets.
                                    Takes the model, the collection type (D_TAX or D_VAT), the current tax brackets, the calculation interval and the collected tax as a parameter and returns the adjusted tax brackets.
    
    Data for tax and VAT collection and redistribution.
    The interval for tax calculation and tax redistribution can be different. In that case, partial collection and redistribution is handled at redistribution intervals.
    At the last interval all remaining taxes are collected and redistributed.
"""
struct FixedTaxScheme{C <: FixedDecimal, FT, FV, FI, FD} <: TaxScheme{C}
    type::TAX_TYPE
    tax_recipients::Int
    tax_calculation_interval::Int
    tax_redistribution_interval::Int
    get_tax::FT
    vat_interval::Int
    get_vat::FV
    deduct_vat_from_taxes::Bool
    initial_income!::FI
    adjust_distribution!::FD

    FixedTaxScheme(tax_type::TAX_TYPE;
                    tax_recipients::Int = 0,
                    tax_calculation_interval::Int = MONTH,
                    tax_redistribution_interval::Int = MONTH,
                    get_tax::Function,
                    vat_interval::Real = tax_calculation_interval,
                    get_vat::Function = (_, _) -> 0,
                    deduct_vat_from_taxes::Bool = false,
                    initial_income!::Union{Nothing, Function} = nothing,
                    adjust_distribution!::Union{Nothing, Function}) = new{Currency,
                                                                            typeof(get_tax),
                                                                            typeof(get_vat),
                                                                            typeof(initial_income!),
                                                                            typeof(adjust_distribution!)}(
                                                                            tax_type,
                                                                            tax_recipients,
                                                                            tax_calculation_interval,
                                                                            min(tax_redistribution_interval, tax_calculation_interval),
                                                                            get_tax,
                                                                            vat_interval,
                                                                            get_vat,
                                                                            deduct_vat_from_taxes,
                                                                            initial_income!,
                                                                            adjust_distribution!)
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
    properties[:tax_recipients] = create_tax_recipients(model, tax_scheme.tax_recipients)

    properties[:tax_redistribution_step] = 0

    properties[:data_collected_taxes] = CUR_0 # For data purposes
    properties[:data_collected_vat] = CUR_0 # For data purposes
    properties[:data_tax_faliures] = 0 # When the full tax can not be paid.
    properties[:data_vat_faliures] = 0 # WHen the full VAT can not be paid.

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
                                                    tax_scheme.get_tax))
    elseif tax_scheme.type == INCOME_TAX
        add_model_behavior!(model,
                            m -> calculate_income_taxes!(m,
                                                        tax_scheme.tax_calculation_interval,
                                                        tax_scheme.get_tax))
    end

    if tax_scheme.type != NO_TAX
        add_model_behavior!(model, m -> collect_and_distribute_taxes!(m,
                                                                    tax_scheme.tax_calculation_interval, # Make sure last cycle taxes are collected and redistributed before new calculation.
                                                                    tax_scheme.tax_redistribution_interval,
                                                                    tax_scheme.adjust_distribution!))
    end

    if tax_scheme.get_vat(model, tax_scheme.vat_interval) != 0
        add_model_behavior!(model,
                            m -> collect_and_distribute_vat!(m,
                                                tax_scheme.vat_interval,
                                                tax_scheme.get_vat,
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

function collect_and_distribute_vat!(model::ABM, vat_interval::Int, get_vat::Function, deduct_vat_from_taxes::Bool)
    if mod(get_step(model), vat_interval) == 0
        collected_vat = CUR_0

        for actor in allagents(model)
            balance = get_balance(actor)
            vat_to_pay = Currency(actor.vat_eligible * get_vat(model, vat_interval))

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
        adjust_distribution! = model.adjust_distribution!

        if isnothing(adjust_distribution!)
            amount_to_distribute = collected_vat
        else
            amount_to_distribute = adjust_distribution!(model, D_VAT, collected_vat)
        end

        distribute_amount!(model, amount_to_distribute, :data_vat_share)
    end
end

function calculate_taxes!(model::ABM,
                        tax_calculation_interval::Int,
                        tax_free::Function,
                        get_tax::Function,
                        taxable::Function)                   
    if mod(get_step(model), tax_calculation_interval) == 0
        for actor in allagents(model)
            taxable_amount = taxable(actor) - actor.tax_deduction

            tax_to_pay = calculate_time_range_demurrage(taxable_amount,
                                                        make_tiers(get_tax(model, tax_calculation_interval)),
                                                        tax_free(actor),
                                                        tax_calculation_interval,
                                                        tax_calculation_interval,
                                                        false)

            actor.tax_to_pay = tax_to_pay
            actor.taxable_income = CUR_0
            actor.tax_deduction = CUR_0

            # Temp
            if tax_to_pay < 0
                taxable_amount = taxable(actor)
                tax_deduction = actor.tax_deduction
                throw("Tax to pay < 0: $tax_to_pay - Taxable = $taxable_amount - Tax deduction = $tax_deduction")
            end

            if tax_to_pay > 0 && tax_to_pay > asset_value(get_balance(actor), SUMSY_DEP)
                income = actor.income
                expenses = actor.expenses
                b = asset_value(get_balance(actor), SUMSY_DEP)
                throw("$Taxes - $tax_to_pay - higher than balance $b - Income = $income - Expenses = $expenses - Taxable amount = $taxable_amount")
            end
            # End temp
        end

        model.tax_redistribution_step = 0
    end
end

function calculate_income_taxes!(model::ABM,
                                tax_calculation_interval::Int,
                                get_tax::Function)    
    calculate_taxes!(model,
                    tax_calculation_interval,
                    a -> 0, # Tax free is in tax brackets
                    get_tax,
                    a -> a.taxable_income)
end

function calculate_dem_taxes!(model,
                            tax_calculation_interval::Int,
                            get_dem_tax::Function)
    calculate_taxes!(model,
                    tax_calculation_interval,
                    a -> get_dem_free(get_balance(a)), # Dem free is actor dependant
                    get_dem_tax,
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

function collect_and_distribute_taxes!(model::ABM,
                                        calculation_interval::Int,
                                        redistribution_interval::Int,
                                        adjust_distribution!::Union{Nothing, Function})
    step = get_step(model)

    if mod(step, redistribution_interval) == 0 || mod(step, calculation_interval) == 0 # Redistribute before new calculation
        tax_coefficient = calculation_interval - model.tax_redistribution_step
        collected_tax = CUR_0

        for actor in allagents(model)
            balance = get_balance(actor)
            # value = asset_value(balance, SUMSY_DEP) # Temp
            tax_slice = Currency(actor.tax_to_pay / tax_coefficient)
                                                    
            if !book_asset!(balance, SUMSY_DEP, -tax_slice)
                tax_slice = asset_value(balance, SUMSY_DEP)
                book_asset!(balance, SUMSY_DEP, -tax_slice)
                model.data_tax_faliures += 1
            end

            # if step > 1 && tax_slice > 0 && asset_value(balance, SUMSY_DEP) < 0
            #     throw("Step $step - Taxes pushed balance in red: $value - tax slice: $tax_slice")
            # end

            actor.tax_to_pay -= tax_slice
            actor.data_taxed_amount += tax_slice
            actor.data_paid_tax += tax_slice
            collected_tax += tax_slice
        end

        model.data_collected_taxes += collected_tax

        if isnothing(adjust_distribution!)
            amount_to_distribute = collected_tax
        else
            amount_to_distribute = adjust_distribution!(model, D_TAX, calculation_interval, collected_tax)
        end

        distribute_amount!(model, amount_to_distribute, :data_tax_share)
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