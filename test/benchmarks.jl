using BenchmarkTools
using Delve.Manuals

# Vector versus ManualVector
function fill_vector()
    a = Vector{Int}(10^5)
    for i in 1:10^5
        a[i] = i
    end
end

function fill_paged_vector()
    a = ManualVector{Int}(10^5)
    for i in 1:10^5
        a[i] = i
    end
end

function vector_bench()
    println("Vector")
    @benchmark fill_vector()

    println("ManualVector")
    @benchmark fill_paged_vector()
end
