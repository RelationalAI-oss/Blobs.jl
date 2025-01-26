using Blobs, BenchmarkTools

@eval struct MixedStruct10
    $((:($(Symbol("f$i"))::Float64) for i in 1:5)...)
    $((:($(Symbol("x$i"))::Int64) for i in 1:5)...)
end
m10 = Blobs.malloc(MixedStruct10)

@eval struct MixedStruct100
    $((:($(Symbol("f$i"))::Float64) for i in 1:50)...)
    $((:($(Symbol("x$i"))::Int64) for i in 1:50)...)
end
m100 = Blobs.malloc(MixedStruct100)

@btime Blobs.malloc(MixedStruct10)
@btime Blobs.malloc(MixedStruct100)

@btime $(m10)[]
@btime $(m100)[]

@btime $(m10)[] = $(m10[])
@btime $(m100)[] = $(m100[])

@btime $(m10).x5[]
@btime $(m100).x5[]
@btime $(m100).x50[]

@btime $(m10).f5[] = 0
@btime $(m10).x5[] = 0
@btime $(m100).f5[] = 0
@btime $(m100).x5[] = 0
@btime $(m100).x50[] = 0

