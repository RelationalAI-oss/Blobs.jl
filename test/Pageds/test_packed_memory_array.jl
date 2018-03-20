using Base.Test
using Delve
using Delve.Pageds

# @testset "Construction from pairs" begin
#     pma = Paged{PackedMemoryArray{Int,Float64}}(1=>0.1, 2=>0.2)
#     @test length(pma) == 2
#     @test pma[1] == 0.1
#     @test pma[2] == 0.2
# end
#
# @testset "Construction from dictionary" begin
#     d = Dict{Int,Float64}(1=>0.1, 2=>0.2)
#     pma = PackedMemoryArray(d)
#     @test length(pma) == 2
#     @test pma[1] == 0.1
#     @test pma[2] == 0.2
# end

@testset "Insertions" begin
    pma = Paged{PackedMemoryArray{Int,Int}}(16)
    for i in 1:10
        pma[i]=i
    end
    for (i,(k,v)) in enumerate(pma)
        @test i == k
        @test k == v
    end
end

@testset "InsertionsAndDeletions" begin
    pma = Paged{PackedMemoryArray{Int,Int}}(16)
    for i in 1:10
        pma[i]=i
    end
    for i in 2:2:10
        delete!(pma, i)
    end
    @test length(pma) == 5
    for i in 1:2:10
        @test (pma[i]) == i
    end
end
