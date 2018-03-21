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
    for i in 1:16
        pma[i]=i
    end
    for (i,(k,v)) in enumerate(pma)
        @test i == k
        @test k == v
    end
end

@testset "InsertionsAndDeletions" begin
    pma = Paged{PackedMemoryArray{Int,Int}}(16)
    for i in 1:16
        pma[i]=i
    end
    for i in 2:2:16
        delete!(pma, i)
    end
    @test length(pma) == 8
    for i in 1:2:16
        @test (pma[i]) == i
    end
end

@testset "Overwriting existing values" begin
    pma = Paged{PackedMemoryArray{Int,Int}}(16)
    for i in 1:16
        pma[i]=i
    end
    for i in 1:16
        pma[i]=2*i
    end
    @test length(pma) == 16
    for i in 1:16
        @test pma[i] == 2*i
    end
end

@testset "Exceptions" begin
    pma = Paged{PackedMemoryArray{Int,Int}}(16)
    for i in 1:16
        pma[i]=i
    end
    @test_throws ErrorException pma[17]=17
    @test_throws KeyError pma[0]
    @test_throws KeyError pma[17]

    @test_throws ArgumentError Paged{PackedMemoryArray{Int,Int}}(15)
    @test_throws ArgumentError Paged{PackedMemoryArray{Int,Int}}(2)
end
