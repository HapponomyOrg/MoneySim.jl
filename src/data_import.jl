using CSV
using DataFrames

function rename_headers!(path::String = "/Users/stef/Programming/Visual Studio/MoneySim.jl/data/")
    cd(path)

    for dir in readdir()
        if dir != ".DS_Store"
            cd(path * dir)

            for file in readdir()
                if file != ".DS_Store"
                    data = CSV.read(file, DataFrame)

                    for i in 3:length(names(data))
                        index = findlast('\n', names(data)[i]) + 1
                        rename!(data, names(data)[i] => names(data)[i][index:end])
                    end

                    CSV.write(file, data)
                end
            end
        end
    end
end