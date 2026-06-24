using EconoSim
using StaticArrays

struct ClearingMatrix{M, V}
    matrix::M
    clearing_vector::V
end

function ClearingMatrix(num_actors::Int)
    global n = num_actors
    matrix = @SMatrix [(i == j ? nothing : MVector{2, Currency}(CUR_0, CUR_0)) for i in 1:n, j in 1:n]
    clearing_vector = @MVector [CUR_0 for _ in 1:n]
    
    return ClearingMatrix{typeof(matrix), typeof(clearing_vector)}(matrix, clearing_vector)
end

function transaction!(ml_matrix, souce_index::Int, destination_index::Int, amount::Real)
    if souce_index != destination_index
        ml_matrix[souce_index, destination_index][1] += amount
        ml_matrix[souce_index, destination_index][2] -= amount
    end

    return ml_matrix
end

function clear!(ml_matrix)
end