using Random
using Intervals

abstract type TaxScheme{C <: FixedDecimal} end

@enum CollectionType D_TAX D_VAT

const TAX_CEILING = Percentage(0.95)
const TAX_FLOOR = Percentage(0.001)

"""
    struct StateTaxScheme{C <: FixedDecimal} <: TaxScheme{C}
        * type: TAX_TYPE
        * tax_recipients: Int - The number of tax recipients.
        * tax_calculation_interval: Int - The interval for tax calculation.
        * tax_redistribution_interval: Int - The interval to collect and distribute taxes. Must be <= tax calculation interval.
        * get_tax_brackets: Function - Returns the tax brackets. Can be DemSettings or DemTiers. Takes the model and calculation_interval as parameters.
        * vat_interval: Int - The interval vor VAT collection.
        * get_vat: Function - Get the VAT rate. Takes the model and calculation interval as parameters. Returns a number between 0 and 1.
        * initial_income!: Function - Set the initial income of the actors.
        * adjust_tax!: Function - Adjust the tax brackets.
                                    Takes the model, the collection type (D_TAX or D_VAT), the current tax brackets, the calculation interval and the collected tax as a parameter and returns the adjusted tax brackets.
    
    Data for tax and VAT collection and redistribution.
    The interval for tax calculation and tax redistribution can be different. In that case, partial collection and redistribution is handled at redistribution intervals.
    At the last interval all remaining taxes are collected and redistributed.
"""
struct StateTaxScheme{C <: FixedDecimal, FI, FT, FV, FE, FR, FD} <: TaxScheme{C}
    type::TAX_TYPE
    tax_recipients::Int
    tax_calculation_interval::Int
    tax_redistribution_interval::Int
    initial_income!::FI
    get_tax_brackets::FT
    vat_interval::Int
    get_vat::FV
    deduct_vat_from_taxes::Bool
    get_projected_expenses::FE
    get_target_revenue::FR
    scale_tax_to_target_revenue::Bool
    deficit_spending::Bool
    initial_debt::C
    debt_reduction::FD

    StateTaxScheme(tax_type::TAX_TYPE;
                    tax_recipients::Int = 0,
                    tax_calculation_interval::Int = MONTH,
                    tax_redistribution_interval::Int = MONTH,
                    initial_income!::Union{Nothing, Function} = nothing,
                    get_tax_brackets::Function,
                    vat_interval::Real = tax_calculation_interval,
                    get_vat::Function = (_, _) -> 0,
                    deduct_vat_from_taxes::Bool = false,
                    get_projected_expenses::Function,
                    get_target_revenue::Function = (_, _) -> 0,
                    scale_tax_to_target_revenue::Bool = false,
                    deficit_spending::Bool,
                    initial_debt::Real = 0,
                    debt_reduction::Function) = new{Currency,
                                                    typeof(initial_income!),
                                                    typeof(get_tax_brackets),
                                                    typeof(get_vat),
                                                    typeof(get_projected_expenses),
                                                    typeof(get_target_revenue),
                                                    typeof(debt_reduction)}(
                                                    tax_type,
                                                    tax_recipients,
                                                    tax_calculation_interval,
                                                    min(tax_redistribution_interval, tax_calculation_interval),
                                                    initial_income!,
                                                    get_tax_brackets,
                                                    vat_interval,
                                                    get_vat,
                                                    deduct_vat_from_taxes,
                                                    get_projected_expenses,
                                                    get_target_revenue,
                                                    scale_tax_to_target_revenue,
                                                    deficit_spending,
                                                    initial_debt,
                                                    debt_reduction)
end

function register_income_and_expenses!(model::ABM)
    for actor in allagents(model)
        actor.vat_eligible += actor.income
        actor.taxable_income += actor.income
    end
end

function set_net_income!(model::ABM)
    for actor in allagents(model)
        actor.data_net_income += actor.income
    end
end

function printable(tax_brackets::DemTiers)
    str = ""

    for bracket in tax_brackets
        str *= "["
        str *= replace(replace(string(bracket[1]), " " => ""), ".0000" => "")
        str *= " - "
        str *= replace(replace(string(bracket[2]), "Percentage(" => ""), ")" => "")
        str *= "] "
    end

    return str
end

function initialize_tax_scheme!(model::ABM, tax_scheme::StateTaxScheme)
    properties = abmproperties(model)
    properties[:tax_recipients] = create_tax_recipients(model, tax_scheme.tax_recipients)

    properties[:tax_redistribution_step] = 0

    properties[:data_collected_taxes] = CUR_0 # For data purposes
    properties[:collected_vat] = CUR_0
    properties[:data_collected_vat] = CUR_0 # For data purposes
    properties[:data_tax_faliures] = 0 # When the full tax can not be paid.
    properties[:data_vat_faliures] = 0 # WHen the full VAT can not be paid.

    properties[:debt] = tax_scheme.initial_debt

    properties[:tax_scale] = "[1] "
    properties[:tax_brackets] = printable(make_tiers(tax_scheme.get_tax_brackets(model, tax_scheme.tax_calculation_interval)))
    properties[:projected_expenses] = CUR_0
    properties[:projected_revenue] = CUR_0

    init_income! = tax_scheme.initial_income!

    for actor in allagents(model)
        isnothing(init_income!) ? (actor.income = CUR_0; actor.data_income = CUR_0) : init_income!(actor)

        actor.expenses = CUR_0 # Only to make sure the field exists
        actor.data_expenses = CUR_0

        actor.tax_deduction = CUR_0

        actor.taxable_income = CUR_0
        actor.tax_to_pay = CUR_0
        actor.data_paid_tax = CUR_0
        actor.data_net_income = CUR_0

        actor.vat_eligible = CUR_0
        actor.data_paid_vat = CUR_0

        actor.data_taxed_amount = CUR_0
        actor.data_tax_share = CUR_0
        actor.data_vat_share = CUR_0
    end

    add_model_behavior!(model,
                        m -> register_income_and_expenses!(m))

    if tax_scheme.type == DEMURRAGE_TAX
        add_model_behavior!(model,
                            m -> calculate_dem_taxes!(m,
                                                    tax_scheme.tax_calculation_interval,
                                                    tax_scheme.get_tax_brackets,
                                                    tax_scheme.get_target_revenue,
                                                    tax_scheme.scale_tax_to_target_revenue))
    elseif tax_scheme.type == INCOME_TAX
        add_model_behavior!(model,
                            m -> calculate_income_taxes!(m,
                                                        tax_scheme.tax_calculation_interval,
                                                        tax_scheme.get_tax_brackets,
                                                        tax_scheme.get_target_revenue,
                                                        tax_scheme.scale_tax_to_target_revenue))
    end

    if tax_scheme.get_vat(model, tax_scheme.vat_interval) != 0
        add_model_behavior!(model,
                            m -> collect_and_distribute_vat!(m,
                                                            tax_scheme.vat_interval,
                                                            tax_scheme.get_vat,
                                                            tax_scheme.deduct_vat_from_taxes))
    end

    if tax_scheme.type != NO_TAX
        add_model_behavior!(model, m -> collect_and_distribute_taxes!(m,
                                                                    tax_scheme.tax_calculation_interval, # Make sure last cycle taxes are collected and redistributed before new calculation.
                                                                    tax_scheme.tax_redistribution_interval,
                                                                    tax_scheme.get_projected_expenses,
                                                                    tax_scheme.deficit_spending,
                                                                    tax_scheme.deduct_vat_from_taxes))
    else
        add_model_behavior!(model, m -> set_net_income!(m))
    end
end

function create_tax_recipients(model::ABM, num_tax_recipients::Int)
    tax_recipients = Vector(undef, num_tax_recipients)

    for i in 1:num_tax_recipients
        tax_recipients[i] = model[i]
    end

    return tax_recipients
end

function scale_vat(vat::Real)
   return vat / (1 + vat)
end

function collect_and_distribute_vat!(model::ABM, vat_interval::Int, get_vat::Function, deduct_vat_from_taxes::Bool)
    if mod(get_step(model), vat_interval) == 0
        collected_vat = CUR_0

        for actor in allagents(model)
            balance = get_balance(actor)
            vat_to_pay = Currency(actor.vat_eligible * scale_vat(get_vat(model, vat_interval)))

            if !book_asset!(balance, SUMSY_DEP, -vat_to_pay)
                vat_to_pay = asset_value(balance, SUMSY_DEP)
                book_asset!(balance, SUMSY_DEP, -vat_to_pay)
                model.data_vat_faliures += 1
            end

            if deduct_vat_from_taxes
                actor.tax_deduction += vat_to_pay # Deduct paid VAT from taxes.
            end

            actor.vat_eligible = CUR_0
            actor.data_paid_vat += vat_to_pay

            collected_vat += vat_to_pay
        end

        model.collected_vat += collected_vat
        model.data_collected_vat += collected_vat

        distribute_amount!(model, collected_vat, :data_vat_share)
    end
end

function calculate_revenue(tax_base::Vector{Currency},
                            tax_brackets::DemTiers)
    revenue = CUR_0
    
    for i in eachindex(tax_base)
        revenue += tax_base[i] * tax_brackets[i][2]
    end

    return Currency(revenue)
end

function create_tax_base(actors,
                            tax_brackets::DemTiers,
                            taxable::Function)
    tax_base = zeros(Currency, length(tax_brackets))

    for actor in actors
        taxable_amount = taxable(actor)

        for i in eachindex(tax_brackets)
            if is_right_unbounded(tax_brackets[i][1])
                amount = taxable_amount
            else
                amount = min(span(tax_brackets[i][1]), taxable_amount)
            end

            tax_base[i] += amount
            taxable_amount -= amount
        end
    end

    return tax_base
end

function scale_brackets(tax_base::Vector{Currency},
                        tax_brackets::DemTiers,
                        target_revenue::Currency)
    overall_tax_scale = target_revenue / calculate_revenue(tax_base, tax_brackets)
    tax_scale = overall_tax_scale
    num_brackets = length(tax_brackets)

    counter = 0 # Temp

    while tax_scale != 1
        expandable_revenue = CUR_0
        fixed_revenue = CUR_0
        edge_brackets = 0

        for i in eachindex(tax_base)
            tax_bracket = tax_brackets[i][2]

            if TAX_FLOOR < tax_bracket < TAX_CEILING
                expandable_revenue += tax_base[i] * tax_bracket
            else
                fixed_revenue += tax_base[i] * tax_bracket
            end
        end

        tax_scale = (target_revenue - fixed_revenue) / expandable_revenue
        scaled_tax_brackets = DemTiers()

        for bracket in tax_brackets
            tax_bracket = bracket[2]

            if TAX_FLOOR < tax_bracket < TAX_CEILING
                push!(scaled_tax_brackets, (bracket[1], round(max(TAX_FLOOR, min(TAX_CEILING, tax_bracket * tax_scale)), digits = 2)))
            else
                push!(scaled_tax_brackets, (bracket[1], tax_bracket))
                edge_brackets += 1
            end
        end

        tax_brackets = make_tiers(scaled_tax_brackets)

        edge_brackets == num_brackets && break

        # Temp
        counter += 1
        if counter > 1000
            break
            # throw("Tax brackets: $printable(tax_brackets)")
        end
    end

    return tax_brackets, overall_tax_scale
end

function calculate_taxes!(model::ABM,
                            tax_calculation_interval::Int,
                            get_tax_brackets::Function,
                            taxable::Function,
                            get_target_revenue::Function,
                            scale_tax_to_target_revenue::Bool,
                            taxes_to_subtract::Function)                   
    if mod(get_step(model) - 1, tax_calculation_interval) == 0 # Calculate taxes at beginning of period, not at the end
        tax_scale = 1
        tax_brackets = make_tiers(get_tax_brackets(model, tax_calculation_interval))
        tax_base = create_tax_base(allagents(model), tax_brackets, taxable)

        if scale_tax_to_target_revenue
            tax_brackets, tax_scale = scale_brackets(tax_base,
                                                        tax_brackets,
                                                        get_target_revenue(model, tax_calculation_interval))
        end

        revenue = CUR_0

        for actor in allagents(model)
            actor.data_taxed_amount = taxable(actor)
            tax_to_pay = max(CUR_0, calculate_revenue(create_tax_base([actor],
                                                            tax_brackets,
                                                            taxable),
                                                        tax_brackets) - actor.tax_deduction)

            revenue += tax_to_pay
            actor.tax_to_pay = tax_to_pay
            actor.data_net_income += actor.taxable_income - taxes_to_subtract(tax_to_pay)
            actor.taxable_income = CUR_0
            actor.tax_deduction = CUR_0
        end

        model.tax_redistribution_step = 0

        model.tax_scale *= "[" * string(tax_scale) * "] "
        model.tax_brackets *= printable(tax_brackets)
        model.projected_revenue += revenue
    end
end

function calculate_income_taxes!(model::ABM,
                                tax_calculation_interval::Int,
                                get_tax_brackets::Function,
                                get_target_revenue::Function,
                                scale_tax_to_target_revenue::Bool)    
    calculate_taxes!(model,
                    tax_calculation_interval,
                    get_tax_brackets,
                    a -> a.taxable_income,
                    get_target_revenue,
                    scale_tax_to_target_revenue,
                    t -> t)
end

function calculate_dem_taxes!(model,
                                tax_calculation_interval::Int,
                                get_dem_tax::Function,
                                get_target_revenue::Function,
                                scale_tax_to_target_revenue::Bool)
    calculate_taxes!(model,
                    tax_calculation_interval,
                    get_dem_tax,
                    a -> asset_value(get_balance(a), SUMSY_DEP) - get_dem_free(get_balance(a)),
                    get_target_revenue,
                    scale_tax_to_target_revenue,
                    _ -> CUR_0)
end

function distribute_amount!(model::ABM, amount_to_distribute::Real, share_symbol::Symbol)
    tax_recipients = model.tax_recipients

    if !isempty(tax_recipients)
        share = Currency(amount_to_distribute / length(tax_recipients))

        for actor in tax_recipients
            book_asset!(get_balance(actor), SUMSY_DEP, share)
            setproperty!(actor, share_symbol, getproperty(actor, share_symbol) + share)
        end

        extra = amount_to_distribute - share * length(tax_recipients)

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
                                        get_projected_expenses::Function,
                                        deficit_spending::Bool,
                                        deduct_vat_from_taxes::Bool)
    step = get_step(model)

    if mod(step - 1, redistribution_interval) == 0
        tax_coefficient = calculation_interval - model.tax_redistribution_step
        collected_tax = CUR_0

        for actor in allagents(model)
            balance = get_balance(actor)
            tax_slice = Currency(actor.tax_to_pay / tax_coefficient)
                                                    
            if !book_asset!(balance, SUMSY_DEP, -tax_slice)
                tax_slice = asset_value(balance, SUMSY_DEP)
                book_asset!(balance, SUMSY_DEP, -tax_slice)
                model.data_tax_faliures += 1
            end

            actor.tax_to_pay -= tax_slice
            actor.data_paid_tax += tax_slice
            collected_tax += tax_slice
        end

        model.data_collected_taxes += collected_tax
        projected_expenses = get_projected_expenses(model, redistribution_interval)
        model.collected_vat = CUR_0
        model.projected_expenses += projected_expenses

        if deficit_spending && projected_expenses > collected_tax
            amount_to_distribute =  projected_expenses
        else
            amount_to_distribute = collected_tax
        end

        model.debt += amount_to_distribute - collected_tax

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