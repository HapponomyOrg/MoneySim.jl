using Test
using EconoSim
using MoneySim

# Every test file in this folder (test/sratch.jl is a scratch file, not a test).
@testset "MoneySim" begin
    include("test_utils.jl")
    include("test_inequality.jl")
    include("test_sumsy_params.jl")
    include("test_sumsy_sim.jl")
    include("test_behaviors.jl")
    include("test_yardsale.jl")
    include("test_transaction_sim.jl")
    include("test_consumer_supplier.jl")
    include("test_tax_scheme.jl")
    include("test_simulations.jl")
    include("test_data_analysis.jl")
    include("test_country_simulations.jl")
    include("test_plotting.jl")
end
