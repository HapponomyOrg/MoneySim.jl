using Test
using Agents
using EconoSim
using MoneySim

# Added on 2026-11-11 to cover the port of behaviors.jl to the current EconoSim API
# (get_step, process_debt! returning a tuple, the SuMSy period from the model).

function borrowing_model(; sumsy::SuMSy = SuMSy(100, 0, 0), interval::Int = 10)
    model = create_econo_model(MonetaryActor{Currency, Balance{Currency}})
    properties = abmproperties(model)
    properties[:sumsy_base] = sumsy
    properties[:sumsy_interval] = interval
    properties[:bank] = Balance()

    actor = add_actor!(model, create_monetary_actor!(model, allow_negative_assets = true))
    actor.debts = []

    return model, actor
end

# get_step(model) is abmtime + 1: a new model is at step 1, and the behaviours act at steps 10, 20, ...

@testset "borrow_when_poor" begin
    model, actor = borrowing_model()
    add_model_behavior!(model, borrow_when_poor)

    # Steps 1 to 9 are inside the first period: nothing happens.
    run_econo_model!(model, 9)
    @test asset_value(get_balance(actor), SUMSY_DEP) == 0
    @test isempty(actor.debts)

    # Step 10 starts a period and the actor has less than 100: it borrows 1000 over 20 installments.
    run_econo_model!(model, 1)
    @test asset_value(get_balance(actor), SUMSY_DEP) == 1000
    @test length(actor.debts) == 1
    @test length(actor.debts[1].installments) == 20

    # Step 20: the first installment is paid and no new loan is needed.
    run_econo_model!(model, 10)
    @test asset_value(get_balance(actor), SUMSY_DEP) == 950
    @test length(actor.debts) == 1
    @test length(actor.debts[1].installments) == 19
end

@testset "borrow_when_poor - settled debts are removed" begin
    model, actor = borrowing_model()
    add_model_behavior!(model, borrow_when_poor)

    # Step 10: first loan. Steps 20..200: 19 installments, leaving 50, so a second loan is taken at step 200.
    run_econo_model!(model, 200)
    @test length(actor.debts) == 2
    @test asset_value(get_balance(actor), SUMSY_DEP) == 1050

    # Step 210: the first loan's last installment is paid and the loan is removed; the second pays its first.
    run_econo_model!(model, 10)
    @test length(actor.debts) == 1
    @test length(actor.debts[1].installments) == 19
    @test asset_value(get_balance(actor), SUMSY_DEP) == 950
end

@testset "ubi_borrow_when_poor" begin
    model, actor = borrowing_model()
    add_model_behavior!(model, ubi_borrow_when_poor)

    # The guaranteed income is booked first, so with 100 the actor is not poor and does not borrow.
    run_econo_model!(model, 10)
    @test asset_value(get_balance(actor), SUMSY_DEP) == 100
    @test isempty(actor.debts)
end

@testset "borrow_income" begin
    model, actor = borrowing_model(sumsy = SuMSy(100, 0, 0.1))
    book_asset!(get_balance(actor), SUMSY_DEP, 500)
    add_model_behavior!(model, borrow_income)

    # The net income of a period is borrowed: 100 guaranteed income minus 10% demurrage on 500.
    run_econo_model!(model, 10)
    @test asset_value(get_balance(actor), SUMSY_DEP) == 550
    @test length(actor.debts) == 1
end
